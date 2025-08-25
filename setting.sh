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
# $1: current step, $2: total steps, $3: current task message
show_progress() {
    local current_step=$1
    local total_steps=$2
    local message="$3"
    local percentage=$((current_step * 100 / total_steps))
    local bar_width=40
    local completed_width=$((bar_width * percentage / 100))
    local remaining_width=$((bar_width - completed_width))

    local spinner_char=${spinner_chars:spinner_idx:1}
    spinner_idx=$(((spinner_idx + 1) % ${#spinner_chars}))

    # Create progress bar
    local bar="["
    for ((i=0; i<completed_width; i++)); do bar+="="; done
    for ((i=0; i<remaining_width; i++)); do bar+=" "; done
    bar+="]"

    # Use \r to move to the beginning of the line and \033[K to clear it.
    printf "\r\r\033[K%s %s %d%% (%d/%d) - %s" "$spinner_char" "$bar" "$percentage" "$current_step" "$total_steps" "$message"
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

    # CORRECTED: Explicitly wait and check the exit code to ensure script stops on failure.
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


# --- Script Start ---
echo "🚀 Starting setup for Narnia Integrated Environment on Linux..."
sleep 1

# Define total number of steps
TOTAL_STEPS=15
CURRENT_STEP=0

# Define Miniconda installation path and environment name
MINICONDA_PATH="$HOME/miniconda"
ENV_NAME="Narnia-Lab"

# --- 1. Python Environment Setup (Miniconda) ---

# 1.1 Check for Miniconda installation and proceed
CURRENT_STEP=$((CURRENT_STEP + 1));
if [ ! -d "$MINICONDA_PATH" ]; then
    INSTALL_LOG="$HOME/miniconda_install.log"
    
    run_with_spinner "wget https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh -O miniconda.sh && bash miniconda.sh -b -p \"$MINICONDA_PATH\" && rm miniconda.sh" "Configuring base Python environment (Miniconda)..." "$INSTALL_LOG"
    
    # Verification step to ensure installation was successful
    if [ ! -f "$MINICONDA_PATH/bin/conda" ]; then
        echo "" # Newline
        echo "--------------------------------------------------" >&2
        echo "❌ Miniconda installation failed." >&2
        echo "   Please check the log file for details: $INSTALL_LOG" >&2
        echo "--------------------------------------------------" >&2
        exit 1
    fi
    
    show_progress $CURRENT_STEP $TOTAL_STEPS "Base Python environment configuration complete."
else
    show_progress $CURRENT_STEP $TOTAL_STEPS "Base Python environment is already installed. (Skipping)"
    sleep 1
fi

# 1.2 Initialize Conda
CURRENT_STEP=$((CURRENT_STEP + 1))
if ! grep -q ">>> conda initialize >>>" ~/.bashrc; then
    run_with_spinner "\"$MINICONDA_PATH/bin/conda\" init bash" "Setting up Conda in your shell environment..."
    show_progress $CURRENT_STEP $TOTAL_STEPS "Shell environment setup complete."
else
    show_progress $CURRENT_STEP $TOTAL_STEPS "Conda is already set up in your shell environment. (Skipping)"
    sleep 1
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
run_with_spinner "\"$CONDA_EXEC\" update -n base -c defaults conda -y --quiet" "Updating Conda packages..."
show_progress $CURRENT_STEP $TOTAL_STEPS "Conda package update complete."

# 1.5 Create Conda virtual environment
CURRENT_STEP=$((CURRENT_STEP + 1));
# CORRECTED: Removed unnecessary backslash before the variable.
if ! "$CONDA_EXEC" env list | grep -q "$ENV_NAME"; then
    run_with_spinner "\"$CONDA_EXEC\" create -n \"$ENV_NAME\" -y python=3.10 --quiet" "Creating Narnia-Lab environment..."
    show_progress $CURRENT_STEP $TOTAL_STEPS "Narnia-Lab environment creation complete."
else
    show_progress $CURRENT_STEP $TOTAL_STEPS "Narnia-Lab environment already exists. (Skipping)"
    sleep 1
fi


# --- 2. Node.js Environment and Narnia Lab Setup ---

# 2.1 Install NVM
CURRENT_STEP=$((CURRENT_STEP + 1));
if [ ! -d "$HOME/.nvm" ]; then
    LATEST_NVM_VERSION=$(curl -s https://api.github.com/repos/nvm-sh/nvm/releases/latest | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
    if [ -z "$LATEST_NVM_VERSION" ]; then
        LATEST_NVM_VERSION="v0.39.7"
    fi
    run_with_spinner "curl -s -o- https://raw.githubusercontent.com/nvm-sh/nvm/$LATEST_NVM_VERSION/install.sh | bash" "Preparing Node.js version manager ($LATEST_NVM_VERSION)..."
    show_progress $CURRENT_STEP $TOTAL_STEPS "Node.js version manager setup complete."
else
    show_progress $CURRENT_STEP $TOTAL_STEPS "Node.js version manager (NVM) is already installed. (Skipping)"
    sleep 1
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
    # Source nvm script again to update the current shell environment
    [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
else
    show_progress $CURRENT_STEP $TOTAL_STEPS "Node.js (LTS) is already installed. (Skipping)"
    sleep 1
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
    sleep 1
fi

# 2.4 Create Gemini CLI settings file
CURRENT_STEP=$((CURRENT_STEP + 1));
if [ ! -f "$HOME/.gemini/settings.json" ]; then
    run_with_spinner "mkdir -p \"$HOME/.gemini\" && printf '{\n  \"selectedAuthType\": \"oauth-personal\"\n}' > \"$HOME/.gemini/settings.json\"" "Setting up CLI authentication..."
    show_progress $CURRENT_STEP $TOTAL_STEPS "CLI authentication setup complete."
else
    show_progress $CURRENT_STEP $TOTAL_STEPS "CLI authentication is already configured. (Skipping)"
    sleep 1
fi


# --- 3. Default Environment and Alias Setup ---

# 3.1 Set up automatic activation in .bashrc
CURRENT_STEP=$((CURRENT_STEP + 1));
if ! grep -qxF "conda activate $ENV_NAME" ~/.bashrc; then
    run_with_spinner "echo \"conda activate $ENV_NAME\" >> ~/.bashrc" "Configuring automatic environment activation..."
    show_progress $CURRENT_STEP $TOTAL_STEPS "Automatic environment activation configured."
else
    show_progress $CURRENT_STEP $TOTAL_STEPS "Automatic environment activation is already set up. (Skipping)"
    sleep 1
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

# 결과 저장 디렉토리 생성
mkdir -p "$OUTPUT_DIR"

# 1. 사용자에게 분석 범위 선택받기
echo "어떤 범위의 프롬프트를 분석하시겠습니까?"
select mode in "최신 로그 파일 1개" "오늘 하루 동안의 모든 로그" "취소"; do
    case $mode in
        "최신 로그 파일 1개" )
            ANALYSIS_TITLE="✅ 최신 Gemini CLI 대화 로그 분석을 시작합니다..."
            LOG_FILES=$(find "$LOG_DIR" -type f -name "logs.json" -printf '%T@ %p\n' 2>/dev/null | sort -n | tail -n 1 | cut -d' ' -f2-)
            break
            ;;
        "오늘 하루 동안의 모든 로그" )
            ANALYSIS_TITLE="✅ 오늘의 Gemini CLI 대화 로그 분석을 시작합니다..."
            LOG_FILES=$(find "$LOG_DIR" -type f -name "logs.json" -mtime 0 2>/dev/null)
            break
            ;;
        "취소" )
            echo "작업을 취소했습니다."
            exit 0
            ;;
        * )
            echo "잘못된 선택입니다. 1, 2, 3 중 하나의 숫자를 입력하세요."
            ;;
    esac
done

# 2. 로그 파일 분석 시작
echo "--------------------------------------------------"
echo "$ANALYSIS_TITLE"

if [ -z "$LOG_FILES" ]; then
  echo "❌ 오류: 선택한 범위에서 'logs.json' 파일을 찾을 수 없습니다."
  exit 1
fi
echo "🔍 분석 대상 로그 파일들을 찾았습니다:"
echo "$LOG_FILES"


# 3. 모든 로그 파일에서 프롬프트를 추출하여 하나의 파일에 저장
# 먼저 prompts.txt 파일을 비움
> "${PROMPT_FILE}"

for LOG_FILE in $LOG_FILES; do
  # jq: JSON 처리기. 각 로그 파일에서 type이 "user"인 항목의 message 값을 추출하여 PROMPT_FILE에 추가(>>)
  jq -r '.[] | select(.type == "user") | .message' "${LOG_FILE}" >> "${PROMPT_FILE}"
done


# -s 옵션: 파일이 존재하는지 그리고 크기가 0보다 큰지 확인
if [ ! -s "${PROMPT_FILE}" ]; then
  echo "❌ 오류: 로그 파일에서 프롬프트를 추출하지 못했습니다."
  echo "   로그 파일들의 JSON 구조를 확인하고, 스크립트의 jq 필터를 수정해야 할 수 있습니다."
  rm "${PROMPT_FILE}" # 내용이 없는 파일도 삭제
  exit 1
fi
echo "👍 프롬프트를 성공적으로 추출하여 '${PROMPT_FILE}'에 저장했습니다."


# 4. 저장된 프롬프트를 Gemini에게 보내 분석 및 개선안 요청
echo "🤖 Gemini에게 프롬프트 개선 방안을 요청합니다..."
echo "------------------- 분석 결과 -------------------"

# 분석을 요청하는 질문 (Meta-Prompt)
META_PROMPT="'prompts.txt' 파일에 담긴 아래 프롬프트들을 각각 다음 3단계에 맞춰 분석하고 제안해줘.

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
 rm "${PROMPT_FILE}"
echo "--------------------------------------------------"
echo "✅ 모든 과정이 완료되었습니다."
#echo "   - 분석에 사용된 '${PROMPT_FILE}' 파일은 현재 위치에 보존됩니다."
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


# --- Complete ---
# Unset the error trap
trap - ERR
show_progress $TOTAL_STEPS $TOTAL_STEPS "All setup complete!"
echo "" # Move to the next line after the progress bar
echo ""
echo "🎉 Narnia Integrated Environment setup completed successfully! 🎉"
echo ""
echo "--- ⚠️ IMPORTANT ---"
echo "To apply all changes, you must close the current terminal and open a new one."
echo "The new terminal will start with the '($ENV_NAME)' environment."
echo ""
echo "--- How to Use ---"
echo ""
echo "In the new terminal, navigate to your desired working directory and type 'narnia'."
echo "On the first run, you will need to log in with your Google account as prompted."
echo "Now, the CLI logo and name will be changed automatically when you run the 'narnia' command."
echo "You can also use 'narnia-feedback' to analyze your prompt history."
echo ""
echo "------------------"

