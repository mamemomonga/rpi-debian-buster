all:
	./builder.sh apt
	./builder.sh rootfs
	./builder.sh setup
	./builder.sh image
