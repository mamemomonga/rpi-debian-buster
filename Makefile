all:
	./builder.sh apt
	./builder.sh rootfs
	./builder.sh setup
	./builder.sh image
	$(MAKE) compress

compress:
	sudo chown $(shell id -u):$(shell id -g) var
	sudo chown $(shell id -u):$(shell id -g) var/image.img
	xz -9 --threads=8 var/image.img

clean:
	sudo rm -rf var/rootfs

.PHONY: all clean compress
