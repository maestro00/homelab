#!/bin/bash
# utils.sh - Utility functions for bash scripts

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_debug() {
    echo -e "${BLUE}[DEBUG]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

# Function to check if command was successful
check_result() {
    if [ $? -eq 0 ]; then
        print_status "$1 successful"
    else
        print_error "$1 failed"
        exit 1
    fi
}

# Function to check if a variable is set and not empty
check_var() {
    local var_name="$1"
    local var_value="$2"

    if [ -z "$var_value" ] || [ "$var_value" = "null" ]; then
        print_error "Variable '$var_name' is not set or empty"
        exit 1
    fi
}

# Function to validate URL response
validate_response() {
    local response="$1"
    local operation_name="$2"

    if echo "$response" | grep -q '"error"'; then
        print_error "$operation_name failed: $response"
        exit 1
    fi
}

# Function to print a separator line
print_separator() {
    echo "=========================================="
}

# Function to print section header
print_section() {
    echo ""
    print_separator
    echo -e "${PURPLE}$1${NC}"
    print_separator
}
