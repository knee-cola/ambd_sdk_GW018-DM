
.PHONY: all clean flash debug setup mp generate_secrets

#*****************************************************************************#
#                               Object FILE LIST                              #
#*****************************************************************************#
OBJS = 

#*****************************************************************************#
#                        RULES TO GENERATE TARGETS                            #
#*****************************************************************************#

# Generate AP secrets before building
generate_secrets:
	@echo "Generating captive portal secrets..."
	@python3 ../../../../tools/generate_ap_secrets.py --project-dir ../../

# Define the Rules to build the core targets
all: generate_secrets CORE_TARGETS
	make -C asdk image3_s
	make -C asdk bootloader
	make -C asdk image2_ns
	
mp: CORE_TARGETS
	make -C asdk mp_image3_s
	make -C asdk bootloader
	make -C asdk mp_image2_ns
	
image2: CORE_TARGETS
	make -C asdk image2_ns
	
setup:
	make -C asdk $(MAKECMDGOALS)

flash:
	make -C asdk gdb

debug:
	make -C asdk debug

xip: CORE_TARGETS
	make -C asdk lib_all
	make -C asdk image3_s
	make -C asdk bootloader
	make -C asdk image2_ns

rom_debug_if_need: CORE_TARGETS
	make -C asdk rom_ns
	make -C asdk rom
	make -C asdk copy_rom

rom2: CORE_TARGETS
	make -C asdk rom2

clean: CORE_TARGETS
	make -C asdk clean

clean_all: CORE_TARGETS
	#make -C asdk clean_rom
	make -C asdk clean_all
	@echo "Cleaning generated secrets..."
	@rm -f ../../inc/inc_hp/provisioning/ap_secrets.h
	@rm -f ../../label.txt ../../wifi_qr.txt

menuconfig: CORE_TARGETS
	make -C asdk menuconfig

gdb: CORE_TARGETS
	make -C asdk gdb #step2: load flash if need
	#please use tools\AmebaZ\Image Tool!!!!!!!!!!!!!!!!!!
	#user guide: WS_20160928_WLAN5_AmebaZ_Image_Tool_User_Guide_1v0

gdbloadrom: CORE_TARGETS
	make -C asdk gdbloadrom #step1: load rom if need


#not use now
#bootloader: CORE_TARGETS
#	make -C asdk bootloader
#img2: CORE_TARGETS
#	make -C asdk image2_ns
#img3: CORE_TARGETS
#	make -C asdk image3_s
#clean_xip: CORE_TARGETS
#	make -C asdk clean_xip
#
#gdb_all: CORE_TARGETS
#	make -C asdk gdb_all
#gdbboot: CORE_TARGETS
#	make -C asdk gdbboot #boot from RAM
#gdbbootxip: CORE_TARGETS
#	make -C asdk gdbbootxip #step3: boot from flash
#gdbloadromall: CORE_TARGETS
#	make -C asdk gdbloadromall #step1: load rom if need
#*****************************************************************************#
#              GENERATE OBJECT FILE 
#*****************************************************************************#
CORE_TARGETS: $(OBJS)

