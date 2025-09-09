#!/bin/bash

# GW018-DM Docker Management Script
# This script manages building and running the GW018-DM firmware flashing Docker container

set -e  # Exit on any error

# Configuration
IMAGE_NAME="gw018-dm-flasher"
IMAGE_TAG="latest"
CONTAINER_NAME="gw018-dm-flasher"
DOCKERFILE_PATH="."

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_info() {
    echo -e "${BLUE}ℹ $1${NC}"
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

print_step() {
    echo -e "${BLUE}=== $1 ===${NC}"
}

# Function to check if Docker is installed and running
check_docker() {
    if ! command -v docker &> /dev/null; then
        print_error "Docker is not installed or not in PATH"
        echo "Please install Docker first: https://docs.docker.com/get-docker/"
        exit 1
    fi
    
    if ! docker info &> /dev/null; then
        print_error "Docker daemon is not running"
        echo "Please start Docker and try again"
        exit 1
    fi
    
    print_success "Docker is available and running"
}

# Function to check if image exists
image_exists() {
    docker image inspect "${IMAGE_NAME}:${IMAGE_TAG}" &> /dev/null
}

# Function to build the Docker image
build_image() {
    print_step "Building Docker Image"
    print_info "Building ${IMAGE_NAME}:${IMAGE_TAG}..."
    
    if ! docker build -t "${IMAGE_NAME}:${IMAGE_TAG}" "${DOCKERFILE_PATH}"; then
        print_error "Docker image build failed"
        exit 1
    fi
    
    print_success "Docker image built successfully"
}

# Function to detect serial devices
detect_serial_devices() {
    local devices=()
    
    # Check for common USB serial devices
    for device in /dev/ttyUSB* /dev/ttyACM*; do
        if [[ -e "$device" ]]; then
            devices+=("$device")
        fi
    done
    
    echo "${devices[@]}"
}

# Function to build Docker run arguments
build_run_args() {
    local run_args=()
    
    # Basic container settings
    run_args+=(
        "--rm"                             # Remove container after exit
        "--interactive"                    # Keep STDIN open
        "--tty"                            # Allocate pseudo-TTY
        "--name" "$CONTAINER_NAME"         # Container name
        # Mount `tools` directory for scripts and tools
        "--volume" "../tools:/workspace/tools"
        # Mount current directory for storing build artifacts
        "--volume" "../build:/workspace/build"
        # Mount the example project which will be used for building
        "--volume" "../project:/workspace/project"
        # Mount the component directory for SDK components
        "--volume" "../component:/workspace/component"
    )
    
    # Detect and add serial devices
    local devices=($(detect_serial_devices))
    if [[ ${#devices[@]} -gt 0 ]]; then
        print_success "Found ${#devices[@]} serial device(s): ${devices[*]}" >&2
        for device in "${devices[@]}"; do
            run_args+=("--device" "$device")
        done
    else
        print_warning "No serial devices found" >&2
        print_info "You can still build firmware, but flashing will require serial device access" >&2
        print_info "Make sure your USB-UART adapter is connected before flashing" >&2
    fi
    
    echo "${run_args[@]}"
}

# Function to run the Docker container
run_container() {
    print_step "Running Docker Container"
    
    # Stop any existing container with the same name
    if docker ps -a --format "table {{.Names}}" | grep -q "^${CONTAINER_NAME}$"; then
        print_info "Stopping existing container..."
        docker rm -f "$CONTAINER_NAME" &> /dev/null || true
    fi
    
    # Build run arguments
    local run_args=($(build_run_args))
    
    print_info "Starting container with interactive flashing guide..."
    echo ""
    print_info "Container will mount current directory as /workspace"
    print_info "All build artifacts and firmware files will be saved locally"
    echo ""
    
    # Run the container
    echo docker run "${run_args[@]}" "${IMAGE_NAME}:${IMAGE_TAG}"

    docker run "${run_args[@]}" "${IMAGE_NAME}:${IMAGE_TAG}"
}

# Function to show usage
show_usage() {
    echo "GW018-DM Docker Management Script"
    echo ""
    echo "Usage: $0 [options]"
    echo ""
    echo "Options:"
    echo "  --build-only    Build the Docker image only (don't run)"
    echo "  --run-only      Run existing image (don't build)"
    echo "  --force-build   Force rebuild even if image exists"
    echo "  --help, -h      Show this help message"
    echo ""
    echo "Default behavior (no options):"
    echo "  1. Check if Docker image exists"
    echo "  2. Build image if necessary"
    echo "  3. Run the container with interactive guide"
    echo ""
    echo "Examples:"
    echo "  $0                  # Build (if needed) and run"
    echo "  $0 --build-only     # Just build the image"
    echo "  $0 --run-only       # Just run existing image"
    echo "  $0 --force-build    # Force rebuild and run"
}

# Main function
main() {
    local build_only=false
    local run_only=false
    local force_build=false
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --build-only)
                build_only=true
                shift
                ;;
            --run-only)
                run_only=true
                shift
                ;;
            --force-build)
                force_build=true
                shift
                ;;
            --help|-h)
                show_usage
                exit 0
                ;;
            *)
                print_error "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done
    
    # Validate conflicting options
    if [[ "$build_only" == true && "$run_only" == true ]]; then
        print_error "Cannot use --build-only and --run-only together"
        exit 1
    fi
    
    print_step "GW018-DM Firmware Flashing Tool"
    echo ""
    
    # Check Docker availability
    check_docker
    
    # Check if Dockerfile exists
    if [[ ! -f "${DOCKERFILE_PATH}/Dockerfile" ]]; then
        print_error "Dockerfile not found in ${DOCKERFILE_PATH}"
        exit 1
    fi
    
    # Build logic
    if [[ "$run_only" != true ]]; then
        if [[ "$force_build" == true ]]; then
            print_info "Force building Docker image..."
            build_image
        elif image_exists; then
            print_success "Docker image ${IMAGE_NAME}:${IMAGE_TAG} already exists"
            if [[ "$build_only" != true ]]; then
                print_info "Use --force-build to rebuild the image"
            fi
        else
            print_info "Docker image ${IMAGE_NAME}:${IMAGE_TAG} not found"
            build_image
        fi
    else
        # Check if image exists when --run-only is specified
        if ! image_exists; then
            print_error "Docker image ${IMAGE_NAME}:${IMAGE_TAG} not found"
            print_info "Run without --run-only to build the image first"
            exit 1
        fi
    fi
    
    # Run logic
    if [[ "$build_only" != true ]]; then
        run_container
    else
        print_success "Build complete. Use '$0 --run-only' to run the container."
    fi
}

# Run main function with all arguments
main "$@"