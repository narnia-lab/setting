#!/bin/bash
# Exit immediately if a command exits with a non-zero status.
set -e

# --- WSL Environment Check ---
# If WSL is detected, change to the Linux home directory to prevent issues
# with running the script from a mounted Windows directory (e.g., /mnt/c/...). 
if grep -qEi "(Microsoft|WSL)" /proc/version &> /dev/null; then
    echo "WSL environment detected. Changing to home directory to ensure all operations are within the Linux filesystem."
    cd "${HOME}"
    echo "Working directory is now: $(pwd)"
fi

# This script installs Miniconda and Node.js in a Linux environment,
# and sets up the Node.js-based Narnia Lab (Gemini CLI).
# It checks if each component is already installed/configured and only performs necessary actions.

# --- Function to handle errors ---
handle_error() {
    # Terminate the spinner process if it's running in the background.
    if [ -n "$spinner_pid" ] && ps -p $spinner_pid > /dev/null; then
        kill $spinner_pid
    fi
    local exit_code=$?
    # $1 (LINENO) is the line number passed by the trap.
    local line_no=$1
    # Print the error message on a new line to avoid being overwritten by the progress bar.
    echo ""
    echo "--------------------------------------------------" >&2
    echo "❌ Error occurred (Line: $line_no, Exit code: $exit_code)" >&2
    echo "Aborting script execution." >&2
    echo "--------------------------------------------------" >&2
    exit $exit_code
}

# --- Set up error trap throughout the script ---
# If an ERR signal occurs (a command exits with a non-zero code), execute the handle_error function.
trap 'handle_error $LINENO' ERR


# --- Spinner icon for progress display ---
spinner_chars="/-\\"
spinner_idx=0

# --- Function to display progress ---
# This function now ignores all arguments and prints a static message.
show_progress() {
    local spinner_char=${spinner_chars:spinner_idx:1}
    spinner_idx=$(((spinner_idx + 1) % ${#spinner_chars}))
    printf "\r\033[K%s Narnia 패키지를 업데이트 중입니다..." "$spinner_char"
}

# --- Function to run commands with a real-time spinner ---
run_with_spinner() {
    local cmd="$1"
    local message="$2"
    local log_file="$3" # Optional log file

    # Default to /dev/null if no log file is provided
    if [ -z "$log_file" ]; then
        log_file="/dev/null"
    fi

    # Run the command in the background, redirecting stdout and stderr.
    eval "$cmd" > "$log_file" 2>&1 &
    local cmd_pid=$!

    # Display spinner animation while the command is running.
    while kill -0 $cmd_pid 2> /dev/null; do
        show_progress $CURRENT_STEP $TOTAL_STEPS "$message"
        sleep 0.1 # Control animation speed
    done

    # Explicitly wait and check the exit code to ensure script stops on failure.
    if ! wait $cmd_pid; then
        echo "" # Newline to clear progress bar
        echo "--------------------------------------------------" >&2
        echo "❌ A background task failed." >&2
        echo "   Task: $message" >&2
        if [ "$log_file" != "/dev/null" ]; then
            echo "   Please check the log for details: $log_file" >&2
        fi
        echo "--------------------------------------------------" >&2
        exit 1 
    fi
}




# Define total number of steps
TOTAL_STEPS=16
CURRENT_STEP=0

# Define Miniconda installation path and environment name
MINICONDA_PATH="$HOME/miniconda"
ENV_NAME="Narnia-Lab"
MINICONDA_JUST_INSTALLED=false # Flag to track if installed in this run

# --- 1. Python Environment Setup (Miniconda) ---

# 1.1 Check for Miniconda installation and proceed
CURRENT_STEP=$((CURRENT_STEP + 1));
if [ ! -d "$MINICONDA_PATH" ]; then
    MINICONDA_JUST_INSTALLED=true
    # CORRECTED: Removed the log file argument. Output will now go to /dev/null.
    run_with_spinner "wget https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh -O miniconda.sh && bash miniconda.sh -b -p \"$MINICONDA_PATH\" && rm miniconda.sh" "Configuring base Python environment (Miniconda)..."
    
    # Verification step to ensure installation was successful
    if [ ! -f "$MINICONDA_PATH/bin/conda" ]; then
        echo "" # Newline
        echo "--------------------------------------------------" >&2
        echo "❌ Miniconda installation failed." >&2
        # CORRECTED: Updated the error message as the log file is no longer created.
        echo "   The installation command failed to execute successfully." >&2
        echo "--------------------------------------------------" >&2
        exit 1
    fi
    
    show_progress $CURRENT_STEP $TOTAL_STEPS "Base Python environment configuration complete."
else
    show_progress $CURRENT_STEP $TOTAL_STEPS "Base Python environment is already installed. (Skipping)"
fi

# 1.2 Initialize Conda
CURRENT_STEP=$((CURRENT_STEP + 1))
if ! grep -q ">>> conda initialize >>>" ~/.bashrc; then
    run_with_spinner "\"$MINICONDA_PATH/bin/conda\" init bash" "Setting up Conda in your shell environment..."
    show_progress $CURRENT_STEP $TOTAL_STEPS "Shell environment setup complete."
else
    show_progress $CURRENT_STEP $TOTAL_STEPS "Conda is already set up in your shell environment. (Skipping)"
fi

CONDA_EXEC="$MINICONDA_PATH/bin/conda"

# 1.3 Accept Anaconda ToS
CURRENT_STEP=$((CURRENT_STEP + 1));
run_with_spinner "yes | ( \
    \"$CONDA_EXEC\" config --set channel_priority strict && \
    \"$CONDA_EXEC\" tos accept --override-channels --channel https://repo.anaconda.com/pkgs/main && \
    \"$CONDA_EXEC\" tos accept --override-channels --channel https://repo.anaconda.com/pkgs/r \
)" "Processing Anaconda ToS agreement..."
show_progress $CURRENT_STEP $TOTAL_STEPS "ToS agreement processing complete."

# 1.4 Update Conda
CURRENT_STEP=$((CURRENT_STEP + 1))
if [ "$MINICONDA_JUST_INSTALLED" = true ]; then
    run_with_spinner "\"$CONDA_EXEC\" update -n base -c defaults conda -y --quiet" "Updating Conda packages..."
    show_progress $CURRENT_STEP $TOTAL_STEPS "Conda package update complete."
else
    show_progress $CURRENT_STEP $TOTAL_STEPS "Conda package update skipped for faster re-runs."
fi

# 1.5 Create Conda virtual environment
CURRENT_STEP=$((CURRENT_STEP + 1));
if ! "$CONDA_EXEC" env list | grep -q "$ENV_NAME"; then
    run_with_spinner "\"$CONDA_EXEC\" create -n \"$ENV_NAME\" -y python=3.10 --quiet" "Creating Narnia-Lab environment..."
    show_progress $CURRENT_STEP $TOTAL_STEPS "Narnia-Lab environment creation complete."
else
    show_progress $CURRENT_STEP $TOTAL_STEPS "Narnia-Lab environment already exists. (Skipping)"
fi


# --- 2. Node.js Environment and Narnia Lab Setup ---

# 2.1 Install NVM
CURRENT_STEP=$((CURRENT_STEP + 1));
if [ ! -d "$HOME/.nvm" ]; then
    # Fetch the latest NVM version dynamically from GitHub.
    LATEST_NVM_VERSION=$(curl -s https://api.github.com/repos/nvm-sh/nvm/releases/latest | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
    
    # If fetching fails, print an error and exit.
    if [ -z "$LATEST_NVM_VERSION" ]; then
        echo "" # Newline for readability
        echo "--------------------------------------------------" >&2
        echo "❌ Error: Could not fetch the latest NVM version." >&2
        echo "   Please check your internet connection and try again." >&2
        echo "--------------------------------------------------" >&2
        exit 1
    fi
    
    run_with_spinner "curl -s -o- https://raw.githubusercontent.com/nvm-sh/nvm/$LATEST_NVM_VERSION/install.sh | bash" "Preparing Node.js version manager ($LATEST_NVM_VERSION)..."
    show_progress $CURRENT_STEP $TOTAL_STEPS "Node.js version manager setup complete."
else
    show_progress $CURRENT_STEP $TOTAL_STEPS "Node.js version manager (NVM) is already installed. (Skipping)"
fi
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"

# 2.2 Install Node.js
CURRENT_STEP=$((CURRENT_STEP + 1))
# Execute after checking if NVM is loaded in the shell
if command -v nvm &> /dev/null && ! (nvm ls default | grep -q "lts\/"); then
    run_with_spinner "nvm install --lts > /dev/null && nvm use --lts > /dev/null && nvm alias default 'lts/*' > /dev/null" "Installing Node.js (LTS)..."
    show_progress $CURRENT_STEP $TOTAL_STEPS "Node.js (LTS) installation complete."
    sleep 0.1
    [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh" > /dev/null 2>&1
else
    show_progress $CURRENT_STEP $TOTAL_STEPS "Node.js (LTS) is already installed. (Skipping)"
fi

# 2.3 Install Gemini CLI
CURRENT_STEP=$((CURRENT_STEP + 1))
if ! command -v gemini &> /dev/null; then
    echo "" # Newline to avoid overwriting the progress bar
    echo "Installing Narnia Lab (CLI)... This may take a moment."
    run_with_spinner "npm install -g @google/gemini-cli" "Installing Narnia Lab (CLI)..."
    show_progress $CURRENT_STEP $TOTAL_STEPS "Narnia Lab (CLI) installation complete."
else
    show_progress $CURRENT_STEP $TOTAL_STEPS "Narnia Lab (CLI) is already installed. (Skipping)"
fi

# 2.4 Create Gemini CLI settings file
CURRENT_STEP=$((CURRENT_STEP + 1));
if [ ! -f "$HOME/.gemini/settings.json" ]; then
    run_with_spinner "mkdir -p \"$HOME/.gemini\" && printf '{\n  \"selectedAuthType\": \"oauth-personal\"\n}' > \"$HOME/.gemini/settings.json\"" "Setting up CLI authentication..."
    show_progress $CURRENT_STEP $TOTAL_STEPS "CLI authentication setup complete."
else
    show_progress $CURRENT_STEP $TOTAL_STEPS "CLI authentication is already configured. (Skipping)"
fi


# --- 2.5. Create Narnia Docs file ---
CURRENT_STEP=$((CURRENT_STEP + 1));
show_progress $CURRENT_STEP $TOTAL_STEPS "Creating Narnia documentation file..."
# Create GEMINI.md file using a Here Document
cat <<'EOF' > "$HOME/.gemini/GEMINI.md"
# 로컬에서 웹 애플리케이션 실행하기

이 문서는 다양한 유형의 웹 프로젝트를 로컬 환경에서 실행하는 방법을 안내합니다.

---

## React 프로젝트 실행하기 (`npm`)

`package.json`을 사용하는 Node.js 기반의 React 프로젝트를 실행하는 방법입니다.

1.  **의존성 설치**:
    프로젝트에 `node_modules` 디렉토리가 없는 경우, 먼저 다음 명령어로 의존성을 설치합니다.
    ```bash
    npm install
    ```

2.  **개발 서버 시작**:
    다음 명령어를 실행하여 React 개발 서버를 시작합니다.
    ```bash
    npm start &
    ```

3.  **IP 주소 확인 및 접속**:
    개발 서버는 일반적으로 3000번 포트를 사용합니다. 다음 명령어로 IP 주소를 확인한 후, 웹 브라우저에서 `http://[IP 주소]:3000`으로 접속하세요.
    ```bash
    hostname -I
    ```

---

## 정적 웹사이트/게임 실행기 (Python HTTP 서버)

HTML, CSS, JavaScript로 구성된 간단한 정적 웹사이트나 웹 기반 게임을 실행하는 방법입니다.

1.  **사용 가능한 포트 찾기**:
    다른 서비스와의 충돌을 피하기 위해 사용 가능한 포트를 찾습니다.
    ```bash
    python3 -c '''import socket; s = socket.socket(socket.AF_INET, socket.SOCK_STREAM); s.bind(("", 0)); print(s.getsockname()[1]); s.close()'''
    ```

2.  **로컬 HTTP 서버 시작**:
    위에서 찾은 포트 번호(`[PORT]`)를 사용하여 Python 내장 HTTP 서버를 시작합니다. `&` 기호는 서버를 백그라운드에서 실행합니다.
    ```bash
    python3 -m http.server [PORT] &
    ```

3.  **로컬 IP 주소 확인**:
    접속할 IP 주소를 확인합니다.
    ```bash
    hostname -I
    ```

4.  **게임 접속**:
    웹 브라우저를 열고 `http://[당신의_IP_주소]:[PORT]` 형식으로 접속합니다.

5.  **문제 해결 (Troubleshooting)**:
    *   **서버 접속 불가**: 선택한 포트가 방화벽에 의해 차단되었을 수 있습니다. 다른 포트를 사용하여 다시 시도해 보세요.
    *   **포트 사용 중 오류**: `Address already in use` 오류가 발생하면, 다른 포트를 찾거나 다음 명령어로 해당 포트를 사용하는 프로세스를 종료하세요.
        ```bash
        lsof -t -i :[PORT] | xargs -r kil
EOF
show_progress $CURRENT_STEP $TOTAL_STEPS "Narnia documentation file creation complete."
sleep 0.5


# --- 3. Default Environment and Alias Setup ---

# 3.1 Set up automatic activation in .bashrc
CURRENT_STEP=$((CURRENT_STEP + 1));
if ! grep -qxF "conda activate $ENV_NAME" ~/.bashrc; then
    run_with_spinner "echo \"conda activate $ENV_NAME\" >> ~/.bashrc" "Configuring automatic environment activation..."
    show_progress $CURRENT_STEP $TOTAL_STEPS "Automatic environment activation configured."
else
    show_progress $CURRENT_STEP $TOTAL_STEPS "Automatic environment activation is already set up. (Skipping)"
fi

# 3.2 Set up 'narnia' command (function) in .bashrc
CURRENT_STEP=$((CURRENT_STEP + 1));
show_progress $CURRENT_STEP $TOTAL_STEPS "Resetting 'narnia' command..."

# Remove any existing narnia alias or function definitions.
sed -i "/alias narnia='gemini'/d" ~/.bashrc > /dev/null 2>&1 || true
sed -i '/# Function to run Narnia customization script and call gemini/,/}/d' ~/.bashrc > /dev/null 2>&1 || true

# Add the new narnia function to .bashrc.
cat <<'EOF' >> ~/.bashrc
# Function to run Narnia customization script and call gemini
narnia() {
    # Check if the .narnia/setting.sh script exists and run it.
    # The script's output is hidden.
    if [ -f "$HOME/.narnia/setting.sh" ]; then
        bash "$HOME/.narnia/setting.sh" >/dev/null 2>&1
    fi
    # Execute the gemini command, passing all arguments.
    gemini "$@"
}
EOF
show_progress $CURRENT_STEP $TOTAL_STEPS "'narnia' command setup complete."


# --- 4. Create Narnia CLI Customization Script ---
CURRENT_STEP=$((CURRENT_STEP + 1));
show_progress $CURRENT_STEP $TOTAL_STEPS "Creating Narnia customization script..."
mkdir -p "$HOME/.narnia"
# Create setting.sh file using a Here Document
cat <<'EOF' > "$HOME/.narnia/setting.sh"
#!/bin/bash

# --- File 1: Replace AsciiArt.js content in all found files ---

# Set the filename to search for
FILENAME_1="AsciiArt.js"

# Set the directory to start the search from
SEARCH_DIR=~/.nvm

# Find all instances of the file
FILE_PATHS_1=$(find "$SEARCH_DIR" -name "$FILENAME_1" 2>/dev/null)

# Check if any files were found
if [ -n "$FILE_PATHS_1" ]; then
  # Loop through each found file path
  echo "$FILE_PATHS_1" | while read -r FILE_PATH; do
    # Overwrite the file content
    cat <<'EOT' > "$FILE_PATH"
/**
 * @license
 * Copyright 2025 Google LLC
 * SPDX-License-Identifier: Apache-2.0
 */

// Short version of the ASCII art logo for 'NARNIA'. (Kerning adjusted)
export const shortAsciiLogo = `
 ██████   █████    ███████     ██████████   ██████   █████ █████    ███████    
░░██████ ░░███   ░███░░░░███  ░░███░░░░███ ░░██████ ░░███ ░░███   ░███░░░░███  
 ░███░███ ░███  ░███    ░░███  ░███   ░███  ░███░███ ░███  ░███  ░███    ░░███ 
 ░███░░███░███  ░████████████  ░████████    ░███░░███░███  ░███  ░████████████ 
 ░███ ░░██████  ░███░░░░░░███  ░███░░███    ░███ ░░██████  ░███  ░███░░░░░░███ 
 ░███  ░░█████  ░███     ░███  ░███ ░░███   ░███  ░░█████  ░███  ░███     ░███ 
 █████  ░░█████ █████    █████ █████ ░░████ █████  ░░█████ █████ █████    █████
░░░░░    ░░░░░ ░░░░░    ░░░░░ ░░░░░   ░░░░ ░░░░░    ░░░░░ ░░░░░ ░░░░░    ░░░░░ 
`;

// Long version of the ASCII art logo for 'NARNIA' with decorative elements on the left. (Slant adjusted)
export const longAsciiLogo = `
  ███         ██████   █████    ███████     ██████████   ██████   █████ █████    ███████    
 ░░░███      ░░██████ ░░███   ░███░░░░███  ░░███░░░░███ ░░██████ ░░███ ░░███   ░███░░░░███  
  ░░░███      ░███░███ ░███  ░███    ░░███  ░███   ░███  ░███░███ ░███  ░███  ░███    ░░███ 
    ░░░███    ░███░░███░███  ░████████████  ░████████    ░███░░███░███  ░███  ░████████████ 
      ███░    ░███ ░░██████  ░███░░░░░░███  ░███░░███    ░███ ░░██████  ░███  ░███░░░░░░███ 
    ███░      ░███  ░░█████  ░███     ░███  ░███ ░░███   ░███  ░░█████  ░███  ░███     ░███ 
  ███░        █████  ░░█████ █████    █████ █████ ░░████ █████  ░░█████ █████ █████    █████
 ░░░         ░░░░░    ░░░░░ ░░░░░    ░░░░░ ░░░░░   ░░░░ ░░░░░    ░░░░░ ░░░░░ ░░░░░    ░░░░░ 
`;

// Tiny version of the ASCII art logo for the first two letters of 'NARNIA', 'NA'. (Slant adjusted)
export const tinyAsciiLogo = `
  ███         ██████   █████    ███████    
 ░░░███      ░░██████ ░░███   ░███░░░░███  
  ░░░███      ░███░███ ░███  ░███    ░░███ 
    ░░░███    ░███░░███░███  ░████████████ 
      ███░    ░███ ░░██████  ░███░░░░░░███ 
    ███░      ░███  ░░█████  ░███     ░███ 
  ███░        █████  ░░█████ █████    █████
 ░░░         ░░░░░    ░░░░░ ░░░░░    ░░░░░ 
`;
EOT
  done
else
  # If no files were found
  echo "Error: Could not find '$FILENAME_1' in the '$SEARCH_DIR' directory."
fi


# --- File 2: Modify userStartupWarnings.js content in all found files ---

# Set the file to search for and the strings to replace
FILENAME_2="userStartupWarnings.js"
SEARCH_STRING="Gemini CLI"
REPLACE_STRING="Narnia Pakage"

# Find all instances of the file
FILE_PATHS_2=$(find "$SEARCH_DIR" -name "$FILENAME_2" 2>/dev/null)

# Check if any files were found
if [ -n "$FILE_PATHS_2" ]; then
  # Loop through each found file path
  echo "$FILE_PATHS_2" | while read -r FILE_PATH; do
    # Modify the string within the file
    sed -i.bak "s/$SEARCH_STRING/$REPLACE_STRING/g" "$FILE_PATH" && rm "${FILE_PATH}.bak"
  done
else
  # If no files were found
  echo "Error: Could not find '$FILENAME_2' in the '$SEARCH_DIR' directory."
fi
EOF
# Grant execute permission to the created script
chmod +x "$HOME/.narnia/setting.sh"
sleep 0.5
show_progress $CURRENT_STEP $TOTAL_STEPS "Narnia customization script creation complete."


# --- 5. Create Narnia Prompt Feedback Script ---
CURRENT_STEP=$((CURRENT_STEP + 1));
show_progress $CURRENT_STEP $TOTAL_STEPS "Creating Narnia prompt feedback script..."
# Create prompt_feedback.sh file using a Here Document
cat <<'EOF' > "$HOME/.narnia/prompt_feedback.sh"
#!/bin/bash

# --- 설정 (필요시 수정) ---
# 로그 파일이 저장되는 디렉토리
LOG_DIR="$HOME/.gemini/tmp"
# 추출된 프롬프트를 임시 저장할 파일 이름
PROMPT_FILE="prompts.txt"
# 분석 결과가 저장될 디렉토리
OUTPUT_DIR="$HOME/gemini_feedback"

# --- 스크립트 시작 ---

# jq 설치 여부 확인
if ! command -v jq &> /dev/null
then
    echo "❌ 오류: 이 스크립트를 실행하려면 'jq'가 필요합니다."
    echo "   'sudo apt-get install jq' 또는 'sudo yum install jq' 등으로 설치해주세요."
    exit 1
fi

# 1. 사용자에게 분석할 시간 입력받기
echo "몇 시간 이전까지의 prompt를 분석하시겠습니까? (숫자만 입력)"
read -p "분석할 시간: " HOURS_AGO

# 입력값이 숫자인지 확인
if ! [[ "$HOURS_AGO" =~ ^[0-9]+$ ]] || [ -z "$HOURS_AGO" ]; then
    echo "❌ 오류: 유효한 숫자를 입력해야 합니다."
    exit 1
fi
# 시간을 분으로 변환 (find -mmin 옵션용)
MINUTES_AGO=$((HOURS_AGO * 60))

# 결과 저장 디렉토리 생성
mkdir -p "$OUTPUT_DIR"

# 2. 로그 파일 분석 시작
ANALYSIS_TITLE="✅ 최근 ${HOURS_AGO}시간 동안의 Gemini 대화 로그 분석을 시작합니다..."
echo "--------------------------------------------------"
echo "$ANALYSIS_TITLE"

# 1단계: 파일 필터링 (최근 N시간 이내에 수정된 logs.json 파일 찾기)
echo "🔍 1단계: 최근 ${HOURS_AGO}시간 내에 수정된 로그 파일을 찾습니다..."
LOG_FILES=$(find "$LOG_DIR" -type f -name "logs.json" -mmin -${MINUTES_AGO} 2>/dev/null)

if [ -z "$LOG_FILES" ]; then
  echo "❌ 오류: 지난 ${HOURS_AGO}시간 동안 수정된 'logs.json' 파일을 찾을 수 없습니다."
  exit 1
fi
echo "👍 분석 대상을 찾았습니다:"
#echo "$LOG_FILES"


# 3. 모든 로그 파일에서 프롬프트를 추출하여 하나의 파일에 저장
echo "🔍 2단계: 파일 내용에서 최근 ${HOURS_AGO}시간 내의 프롬프트를 추출합니다..."
# 먼저 prompts.txt 파일을 비움
> "${PROMPT_FILE}"

# ISO 8601 형식 (UTC)으로 비교 시간 계산
# GNU date (Linux)
if date --version >/dev/null 2>&1; then
    CUTOFF_TIMESTAMP=$(date -u -d"${HOURS_AGO} hours ago" --iso-8601=seconds)
# BSD date (macOS)
else
    CUTOFF_TIMESTAMP=$(date -u -v-${HOURS_AGO}H +"%Y-%m-%dT%H:%M:%SZ")
fi

for LOG_FILE in $LOG_FILES; do
  # 2단계: JSON 내용 필터링
  # jq를 사용해 type이 "user"이고, timestamp가 CUTOFF_TIMESTAMP 이후인 프롬프트만 추출
  # logs.json에 'timestamp' 필드가 ISO 8601 형식으로 저장되어 있다고 가정
  jq -r --arg cutoff_time "$CUTOFF_TIMESTAMP" '.[] | select(.type == "user" and .timestamp > $cutoff_time) | .message' "${LOG_FILE}" >> "${PROMPT_FILE}"
done


# -s 옵션: 파일이 존재하는지 그리고 크기가 0보다 큰지 확인
if [ ! -s "${PROMPT_FILE}" ]; then
  echo "❌ 오류: 지정된 시간 내에서 프롬프트를 추출하지 못했습니다."
  echo "   - 로그 파일의 JSON에 'timestamp' 필드가 없거나 형식이 다를 수 있습니다."
  echo "   - 또는 해당 시간 내에 작성된 프롬프트가 없을 수 있습니다."
  rm "${PROMPT_FILE}" # 내용이 없는 파일도 삭제
  exit 1
fi
echo "👍 프롬프트를 성공적으로 추출하여 '${PROMPT_FILE}'에 저장했습니다."


# 4. 저장된 프롬프트를 Gemini에게 보내 분석 및 개선안 요청
echo "🤖 Gemini에게 프롬프트 개선 방안을 요청합니다..."
echo "------------------- 분석 결과 -------------------"

# 분석을 요청하는 질문 (Meta-Prompt)
META_PROMPT="'prompts.txt' 파일에 담긴 아래 프롬프트를 각각 다음 3단계에 맞춰 분석하고 제안해줘.

1. **원본 프롬프트**: (내가 작성한 프롬프트 내용)
2. **개선 제안**: (어떻게 바꾸면 좋을지에 대한 구체적인 의견)
3. **개선된 프롬프트**: (2번 의견이 반영된 새로운 프롬프트)"

# command substitution을 사용해 파일 내용과 질문을 하나의 프롬프트로 합쳐서 전달하고, 결과를 변수에 저장
ANALYSIS_RESULT=$(gemini -p "${META_PROMPT}

$(<"${PROMPT_FILE}")")

# 터미널에 결과 출력
echo "$ANALYSIS_RESULT"


# 5. 분석 결과를 마크다운 파일로 저장
TIMESTAMP=$(date +%Y-%m-%d_%H-%M-%S)
OUTPUT_FILE="${OUTPUT_DIR}/feedback_${TIMESTAMP}.md"
echo "$ANALYSIS_RESULT" > "$OUTPUT_FILE"


# 6. 임시 파일 삭제 (주석 처리)
# rm "${PROMPT_FILE}"
echo "--------------------------------------------------"
echo "✅ 모든 과정이 완료되었습니다."
echo "   - 분석에 사용된 '${PROMPT_FILE}' 파일은 현재 위치에 보존됩니다."
echo "   - 분석 결과는 '${OUTPUT_FILE}' 파일에 저장되었습니다."
EOF
# Grant execute permission to the created script
chmod +x "$HOME/.narnia/prompt_feedback.sh"
show_progress $CURRENT_STEP $TOTAL_STEPS "Narnia prompt feedback script creation complete."


# --- 6. Set up 'narnia-feedback' alias ---
CURRENT_STEP=$((CURRENT_STEP + 1));
show_progress $CURRENT_STEP $TOTAL_STEPS "Setting up 'narnia-feedback' alias..."

# Remove any existing narnia-feedback alias.
sed -i "/alias narnia-feedback=/d" ~/.bashrc > /dev/null 2>&1 || true

# Add the new alias to .bashrc.
echo "alias narnia-feedback='bash \$HOME/.narnia/prompt_feedback.sh'" >> ~/.bashrc

show_progress $CURRENT_STEP $TOTAL_STEPS "'narnia-feedback' alias setup complete."


# Remove any existing narnia-feedback alias.
sed -i "/alias narnia-update=/d" ~/.bashrc > /dev/null 2>&1 || true

# Add the new alias to .bashrc.
echo "alias narnia-update='curl -fsSL https://raw.githubusercontent.com/narnia-lab/setting/main/setting.sh | bash'" >> ~/.bashrc


# --- 7. Set up automatic update on login ---
# The code to be added to .profile
AUTO_UPDATE_CODE="# Automatically run narnia-update on login\nnarnia-update"

# Check if the code already exists in .profile to avoid duplicates
if ! grep -qF "narnia-update" ~/.profile 2>/dev/null; then
    echo "" >> ~/.profile # Add a newline for separation
    echo -e "$AUTO_UPDATE_CODE" >> ~/.profile
fi


source ~/.bashrc
# --- Complete ---
# Unset the error trap
trap - ERR
# Clear the spinner line and print the final message
printf "\r\033[K"
echo "업데이트가 완료되었습니다."

