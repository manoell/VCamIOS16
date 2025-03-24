# Configuração do alvo para iPhone com iOS 16.0
TARGET := iphone:clang:latest:16.0
# Processo alvo para injeção (SpringBoard é adequado para tweaks de câmera)
INSTALL_TARGET_PROCESSES = SpringBoard Camera
# Endereço IP do dispositivo (verifique se está correto)
THEOS_DEVICE_IP = 192.168.0.186
# Inclui as regras comuns do Theos
include $(THEOS)/makefiles/common.mk
# Nome do tweak
TWEAK_NAME = VCamTeste
# Arquivos fonte
VCamTeste_FILES = Tweak.x
# Flags de compilação
VCamTeste_CFLAGS = -fobjc-arc -Wno-deprecated-declarations
# Frameworks necessários
VCamTeste_FRAMEWORKS = UIKit Foundation AVFoundation
# Inclui as regras para tweak
include $(THEOS_MAKE_PATH)/tweak.mk
