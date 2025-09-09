# Code Style and Conventions

## General C/C++ Style
- **Language**: Primarily C with some C++ components
- **Naming**: Snake_case for functions and variables, SCREAMING_SNAKE_CASE for constants
- **Headers**: Include guards in .h files
- **Memory Management**: Manual memory management, careful with embedded constraints

## Configuration Pattern
- Feature toggles via CONFIG_EXAMPLE_* macros in platform_opts.h
- Conditional compilation using #if CONFIG_EXAMPLE_FEATURE
- Example pattern:
```c
#define CONFIG_EXAMPLE_SOCKET_TCP_TRX 1
#if CONFIG_EXAMPLE_SOCKET_TCP_TRX
// Feature implementation
#endif
```

## Example Code Structure
- Examples located in `component/common/example/`
- Each example has its own subdirectory
- Main entry point usually named `example_*.c`
- Include example_entry.c registration

## AT Command Style
WiFi configuration uses AT command format:
```c
ATW0=ssid_name
ATW1=password  
ATWC
```

## GPIO and Hardware Access
- Direct register access patterns
- Pin definitions in hardware-specific headers
- Interrupt handlers follow RTL naming conventions

## Memory Constraints
- Embedded system with limited RAM/Flash
- Careful buffer management
- Stack size considerations for dual-core architecture

## Build Artifacts
- Generated images in asdk/image/ directories
- Binary files follow naming convention: `km[0|4]_*.bin`
- OTA files named `OTA_All.bin`