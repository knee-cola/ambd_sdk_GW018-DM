# Task Completion Checklist

## Code Changes
- [ ] Verify changes don't break dual-core build (both project_lp and project_hp)
- [ ] Check CONFIG_EXAMPLE_* flags are properly set in platform_opts.h
- [ ] Ensure memory usage fits embedded constraints
- [ ] Test UART communication doesn't interfere with main functionality

## Build Verification  
- [ ] Clean build: `make clean && make all` in both project directories
- [ ] Check generated binaries exist in asdk/image/ folders
- [ ] Verify image sizes are reasonable for flash memory
- [ ] No compilation warnings or errors

## Testing Requirements
- [ ] Test basic WiFi connectivity (ATW0, ATW1, ATWC commands)
- [ ] Verify TCP socket server starts on port 80
- [ ] Check Zigbee2MQTT can connect via TCP
- [ ] Test OTA update mechanism if modified
- [ ] Verify device boots properly after power cycle

## Hardware Testing (if available)
- [ ] Flash firmware via UART using ImageTool
- [ ] Test WiFi connection to real network  
- [ ] Verify Zigbee2MQTT integration works
- [ ] Check OTA updates work over WiFi
- [ ] Test device stability over extended periods

## Documentation Updates
- [ ] Update README.md if build process changes
- [ ] Update configuration documentation for new features
- [ ] Document any new AT commands or protocols
- [ ] Update Docker build scripts if dependencies change

## Safety Checks
- [ ] Backup original firmware before flashing changes
- [ ] Test recovery procedures work (UART command mode)
- [ ] Verify no security vulnerabilities introduced  
- [ ] Check power consumption hasn't increased significantly