
include $(MAKE_INCLUDE_GEN)

.PHONY: all clean

#*****************************************************************************#
#                               VARIABLES	                              #
#*****************************************************************************#
DIR = $(SRCDIR)

MODULE_IFLAGS = -I$(DIR)./

vpath %.c $(DIR) $(DIR)/provisioning
#*****************************************************************************#
#                               Source FILE LIST                              #
#*****************************************************************************#
CSRC = $(DIR)/main.c

# Captive portal provisioning modules (always include when files exist)
ifneq ($(wildcard $(DIR)/provisioning/provisioning_task.c),)
CSRC += $(DIR)/provisioning/provisioning_task.c
CSRC += $(DIR)/provisioning/dns_captive.c
CSRC += $(DIR)/provisioning/http_portal.c
CSRC += $(DIR)/provisioning/wifi_store.c
endif

#*****************************************************************************#
#                               Object FILE LIST                              #
#*****************************************************************************#
OBJS = $(notdir $(CSRC:.c=.o))

#*****************************************************************************#
#                        RULES TO GENERATE TARGETS                            #
#*****************************************************************************#
all: CLEAN_OBJS CORE_TARGETS COPY_RAM_OBJS
	
#*****************************************************************************#
#              GENERATE OBJECT FILE 
#*****************************************************************************#
CORE_TARGETS: $(OBJS)

#*****************************************************************************#
#                        RULES TO CLEAN TARGETS                               #
#*****************************************************************************#
clean: CLEAN_OBJS
	$(REMOVE) *.o
	$(REMOVE) *.i
	$(REMOVE) *.s
	$(REMOVE) *.d

-include $(DEPS)	
