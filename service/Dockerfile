# Copyright 2026 Google LLC.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     https://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
# Pinned to Python 3.10 to match the runtime the app was previously deployed
# with on Cloud Functions gen2 (--runtime=python310). Google's Cloud Run
# source-deploy Buildpacks no longer offer Python 3.10, and torch==2.3.1 has
# no wheels for the newer versions those buildpacks provide (3.13/3.14).
FROM python:3.10-slim

# ffmpeg provides both the ffmpeg and ffprobe binaries invoked via
# subprocess in service/utils/utils.py (execute_subprocess_commands).
# libsndfile1 is required by spleeter's audio I/O (soundfile/librosa).
RUN apt-get update && apt-get install -y --no-install-recommends \
      ffmpeg \
      libsndfile1 \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY . .

ENV PORT=8080
CMD exec functions-framework --target=gcs_file_uploaded --port=${PORT}
