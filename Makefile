HOME_DIR = $(shell env | egrep "^HOME=" | sed 's/^.*=//g')
COMPONENTS = $(shell ls db*.sh)

install:
	./install.sh
