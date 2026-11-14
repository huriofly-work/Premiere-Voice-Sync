# Thông báo thành phần bên thứ ba

Mã nguồn của Premiere Voice Sync thuộc bản quyền của huriofly-work, bảo lưu mọi
quyền (xem [README](README.md#bản-quyền)). Gói phát hành
`Premiere-Voice-Sync-<version>-Panel.zip` còn chứa các thành phần dưới đây. Mỗi
thành phần giữ giấy phép riêng của tác giả; giấy phép của Premiere Voice Sync
không áp dụng cho chúng.

| Thành phần | File trong gói | Phiên bản và nguồn | Giấy phép |
| --- | --- | --- | --- |
| FFmpeg | `extension/engine/runtime/bin/ffmpeg.exe` | 8.1.2, bản `essentials_build` của [gyan.dev](https://www.gyan.dev/ffmpeg/builds/) | GPL v3 hoặc mới hơn (build với `--enable-gpl --enable-version3`); toàn văn trong `licenses/GPL-3.0.txt` đi kèm |
| whisper.cpp và ggml | `whisper-cli.exe`, `whisper.dll`, `ggml.dll`, `ggml-base.dll`, `ggml-cpu-*.dll`, `parakeet.dll` trong `extension/engine/runtime/bin/` | v1.9.1, bản Windows x64 từ [ggml-org/whisper.cpp](https://github.com/ggml-org/whisper.cpp/releases/tag/v1.9.1) | [MIT](https://github.com/ggml-org/whisper.cpp/blob/v1.9.1/LICENSE) |
| SDL2 | `extension/engine/runtime/bin/SDL2.dll` | Bản đi kèm whisper.cpp v1.9.1 Windows x64 ([libsdl.org](https://www.libsdl.org/)) | [zlib](https://www.libsdl.org/license.php) |
| Model Whisper large-v3-turbo (định dạng ggml) | `extension/engine/runtime/models/ggml-large-v3-turbo.bin` | [huggingface.co/ggerganov/whisper.cpp](https://huggingface.co/ggerganov/whisper.cpp), revision `5359861c739e955e79d9a303bcbc70fb988958b1`; trọng số gốc của [OpenAI Whisper](https://github.com/openai/whisper) | [MIT](https://github.com/openai/whisper/blob/main/LICENSE) |
| Danh sách cụm từ tiếng Việt | `extension/engine/lib/vi-caption-phrases.txt` | Rút gọn từ VnVocab của [RDRsegmenter](https://github.com/datquocnguyen/RDRsegmenter) | Apache 2.0; xem `vi-caption-phrases.NOTICE.txt` và `vi-caption-phrases.LICENSE.txt` đi kèm |

SHA-256 của từng file runtime được khóa trong
[`extension/engine/runtime-lock.json`](extension/engine/runtime-lock.json).

## FFmpeg (GPL v3)

`ffmpeg.exe` là chương trình riêng. Premiere Voice Sync gọi nó như một tiến
trình độc lập để chuyển đổi âm thanh và không liên kết thư viện của FFmpeg vào
mã của mình. FFmpeg được phân phối lại nguyên vẹn, không sửa đổi.

- Toàn văn GPL v3 đi kèm gói ở `licenses/GPL-3.0.txt` (bản gốc của Free
  Software Foundation tại <https://www.gnu.org/licenses/gpl-3.0.txt>, 35 149
  byte, SHA-256
  `3972dc9744f6499f0f9b2dbf76696f2ae7ad8af9b23dde66d6af86c9dfb36986`).
- Mã nguồn FFmpeg 8.1.2 dùng cho bản build này:
  <https://ffmpeg.org/releases/ffmpeg-8.1.2.tar.xz> (danh sách bản phát hành:
  <https://ffmpeg.org/releases/>).
- Bản `essentials_build` còn gộp sẵn một số thư viện bên ngoài. Danh sách thư
  viện và phiên bản có ở trang build của gyan.dev:
  <https://www.gyan.dev/ffmpeg/builds/>. Chạy `ffmpeg.exe -version`
  để xem đúng cấu hình của file trong gói.

## Backend CUDA tải thêm (không nằm trong gói)

Trên máy NVIDIA, người dùng có thể bật tải backend CUDA. Panel tải
`whisper-cublas-12.4.0-bin-x64.zip` trực tiếp từ bản phát hành whisper.cpp
v1.9.1 trên GitHub, kiểm SHA-256 theo `cuda-lock.json` rồi lưu vào
`%LOCALAPPDATA%\PremiereVoiceSync\Backends`. Gói này do dự án whisper.cpp phát
hành, có kèm thư viện CUDA runtime của NVIDIA theo giấy phép của NVIDIA;
Premiere Voice Sync không phân phối lại nó.

## Thông báo bản quyền MIT

whisper.cpp và ggml, Copyright (c) The ggml authors (năm bản quyền đúng như
file [LICENSE của v1.9.1](https://github.com/ggml-org/whisper.cpp/blob/v1.9.1/LICENSE)).
OpenAI Whisper, Copyright (c) 2022 OpenAI.

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

## Thông báo zlib (SDL2)

Simple DirectMedia Layer, Copyright (C) Sam Lantinga (năm bản quyền theo
[giấy phép SDL](https://www.libsdl.org/license.php)).

This software is provided 'as-is', without any express or implied warranty. In
no event will the authors be held liable for any damages arising from the use
of this software.

Permission is granted to anyone to use this software for any purpose,
including commercial applications, and to alter it and redistribute it freely,
subject to the following restrictions:

1. The origin of this software must not be misrepresented; you must not claim
   that you wrote the original software. If you use this software in a
   product, an acknowledgment in the product documentation would be
   appreciated but is not required.
2. Altered source versions must be plainly marked as such, and must not be
   misrepresented as being the original software.
3. This notice may not be removed or altered from any source distribution.
