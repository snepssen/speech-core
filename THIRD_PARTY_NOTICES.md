# Third-party notices

speech-core's own code is MIT, copyright 2026 snepssen. See `LICENSE`.

On Apple platforms, SileroVAD depends on ONNX Runtime through the Swift package
[onnxruntime-swift-package-manager](https://github.com/microsoft/onnxruntime-swift-package-manager)
1.20.0, which links
[ONNX Runtime](https://github.com/microsoft/onnxruntime). Both are MIT, copyright Microsoft Corporation. This repository does not
relicense them. Other platforms do not link the runtime.

## ONNX Runtime

ONNX Runtime 1.20 publishes the following notice. The Swift package uses the
same MIT licence.

```
MIT License

Copyright (c) Microsoft Corporation

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```
