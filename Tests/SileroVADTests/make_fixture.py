#!/usr/bin/env python3
"""Build Fixtures/mean_window.onnx beside this file.

The graph is not Silero. It lets the wrapper tests run without the weights:

  output = mean(context + frame) + 0.001 * state[0, 0, 0] + (sr - 16000)
  stateN = state + 1

`sr - 16000` is zero when the wrapper feeds 16 kHz, and it keeps that input
from being folded away. The state term is zero on the first call and grows
by 0.001 each call, so a dropped state round-trip fails the tests.
"""

import sys
from pathlib import Path

import numpy as np
import onnx
from onnx import TensorProto, helper, numpy_helper
import onnxruntime as ort

BUMP = np.float32(0.001)
CONTEXT = 64
FRAME = 512


def build() -> onnx.ModelProto:
    inputs = [
        helper.make_tensor_value_info("input", TensorProto.FLOAT, [1, "samples"]),
        helper.make_tensor_value_info("state", TensorProto.FLOAT, [2, 1, 128]),
        helper.make_tensor_value_info("sr", TensorProto.INT64, []),
    ]
    outputs = [
        helper.make_tensor_value_info("output", TensorProto.FLOAT, [1, 1]),
        helper.make_tensor_value_info("stateN", TensorProto.FLOAT, [2, 1, 128]),
    ]
    inits = [
        numpy_helper.from_array(np.array([0, 0, 0], np.int64), "starts"),
        numpy_helper.from_array(np.array([1, 1, 1], np.int64), "ends"),
        numpy_helper.from_array(np.array([0, 1, 2], np.int64), "axes"),
        numpy_helper.from_array(np.array([1, 1], np.int64), "shape11"),
        numpy_helper.from_array(np.array([[BUMP]], np.float32), "bump"),
        numpy_helper.from_array(np.float32(16000), "sixteen"),
        numpy_helper.from_array(np.ones((2, 1, 128), np.float32), "ones"),
    ]
    nodes = [
        helper.make_node("ReduceMean", ["input"], ["mean"], axes=[1], keepdims=1),
        helper.make_node("Slice", ["state", "starts", "ends", "axes"], ["first"]),
        helper.make_node("Reshape", ["first", "shape11"], ["first11"]),
        helper.make_node("Mul", ["first11", "bump"], ["state_term"]),
        helper.make_node("Cast", ["sr"], ["sr_f"], to=TensorProto.FLOAT),
        helper.make_node("Sub", ["sr_f", "sixteen"], ["sr_delta"]),
        helper.make_node("Reshape", ["sr_delta", "shape11"], ["sr11"]),
        helper.make_node("Add", ["mean", "state_term"], ["scored"]),
        helper.make_node("Add", ["scored", "sr11"], ["output"]),
        helper.make_node("Add", ["state", "ones"], ["stateN"]),
    ]
    graph = helper.make_graph(nodes, "mean_window", inputs, outputs, inits)
    model = helper.make_model(graph, opset_imports=[helper.make_opsetid("", 17)])
    model.ir_version = 8
    model.doc_string = (
        "speech-core SileroVAD test fixture. Not a voice detector: "
        "mean(input) + 0.001 * state[0,0,0] + (sr - 16000), stateN = state + 1."
    )
    onnx.checker.check_model(model)
    return model


def session(model: onnx.ModelProto, optimize: bool) -> ort.InferenceSession:
    options = ort.SessionOptions()
    options.intra_op_num_threads = 1
    options.graph_optimization_level = (
        ort.GraphOptimizationLevel.ORT_ENABLE_ALL
        if optimize
        else ort.GraphOptimizationLevel.ORT_DISABLE_ALL
    )
    return ort.InferenceSession(model.SerializeToString(), options, providers=["CPUExecutionProvider"])


def run_case(optimize: bool) -> None:
    sess = session(build(), optimize)
    names_in = [item.name for item in sess.get_inputs()]
    names_out = [item.name for item in sess.get_outputs()]
    assert names_in == ["input", "state", "sr"], names_in
    assert names_out == ["output", "stateN"], names_out

    previous = np.zeros(CONTEXT, np.float32)
    state = np.zeros((2, 1, 128), np.float32)

    def push(frame: np.ndarray, sr: int = 16000):
        nonlocal previous, state
        window = np.concatenate([previous, frame]).astype(np.float32)
        out, state_n = sess.run(
            ["output", "stateN"],
            {
                "input": window[None, :],
                "state": state,
                "sr": np.array(sr, np.int64),
            },
        )
        score = np.float32(out.reshape(-1)[0])
        state = state_n
        previous = window[-CONTEXT:]
        return score

    def expect(context: float, frame_value: float, step: int) -> np.float32:
        mean = (np.float32(CONTEXT) * np.float32(context) + np.float32(FRAME) * np.float32(frame_value)) / np.float32(
            CONTEXT + FRAME
        )
        return mean + np.float32(step) * BUMP

    zeros = np.zeros(FRAME, np.float32)
    ones = np.ones(FRAME, np.float32)

    # Silence stays under the off threshold, and the state term counts calls.
    for step in range(100):
        score = push(zeros)
        assert score < np.float32(0.35), (step, score)
        assert abs(float(score) - float(step) * float(BUMP)) < 1e-6, (step, score)

    # Reset, then the 64-sample tail is what the next frame still carries.
    previous = np.zeros(CONTEXT, np.float32)
    state = np.zeros((2, 1, 128), np.float32)
    tail = np.concatenate([np.zeros(FRAME - CONTEXT, np.float32), np.ones(CONTEXT, np.float32)])
    first = push(tail)
    second = push(zeros)
    third = push(zeros)
    mean_tail = np.float32(CONTEXT) / np.float32(CONTEXT + FRAME)
    assert abs(float(first) - float(mean_tail)) < 1e-6, first
    assert abs(float(second) - float(mean_tail + BUMP)) < 1e-6, second
    assert abs(float(third) - float(BUMP * 2)) < 1e-6, third

    # Hysteresis band, uniform frames, default thresholds.
    previous = np.zeros(CONTEXT, np.float32)
    state = np.zeros((2, 1, 128), np.float32)
    quiet = push(np.full(FRAME, np.float32(0.45)))
    loud = push(ones)
    held = push(np.full(FRAME, np.float32(0.325)))
    dropped = push(zeros)
    for label, got, exp in [
        ("quiet", quiet, expect(0, 0.45, 0)),
        ("loud", loud, expect(0.45, 1, 1)),
        ("held", held, expect(1, 0.325, 2)),
        ("dropped", dropped, expect(0.325, 0, 3)),
    ]:
        assert abs(float(got) - float(exp)) < 1e-5, (label, got, exp, optimize)
    assert np.float32(0.35) <= quiet < np.float32(0.5)
    assert loud >= np.float32(0.5)
    assert np.float32(0.35) <= held < np.float32(0.5)
    assert dropped < np.float32(0.35)

    # sr moves the score exactly by the difference from 16 kHz.
    previous = np.zeros(CONTEXT, np.float32)
    state = np.zeros((2, 1, 128), np.float32)
    shifted = push(zeros, sr=16001)
    assert abs(float(shifted) - 1.0) < 1e-6, shifted

    # Equality at the thresholds: zeros are an exact 0, then an exact bump.
    previous = np.zeros(CONTEXT, np.float32)
    state = np.zeros((2, 1, 128), np.float32)
    exact0 = push(zeros)
    exact1 = push(zeros)
    assert exact0 == np.float32(0), exact0
    assert exact1 == BUMP, (exact1, BUMP, exact1.view(np.uint32), BUMP.view(np.uint32))

    print("ok", "optimized" if optimize else "unoptimized", "bytes", len(build().SerializeToString()))


def main() -> None:
    destination = sys.argv[1] if len(sys.argv) > 1 else str(
        Path(__file__).resolve().parent / "Fixtures" / "mean_window.onnx"
    )
    onnx.save(build(), destination)
    run_case(False)
    run_case(True)
    print("wrote", destination)


if __name__ == "__main__":
    main()
