# Raspberry Pi3, Ri4 向け Debian10 aarch64 ビルドツール

* Raspberry Pi3用
* GPUメモリ16MB
* シリアルコンソール有効(115200 baud)
* sshd有効
* dhcp有効
* vim, ntpd, sudo
* rootユーザのパスワードはなし
* adminユーザのパスワードは debian
* adminユーザはsudoでrootになることが可能
* カレントディレクトリに authorized\_keys ファイルがある場合は、それをadminユーザのauthorized\_keysとして登録します

## 構築環境

* Debian10 amd64
* /mnt を一時的なマウントポイントとして利用します
* sudoでrootユーザになれる必要がある

## コマンド一覧

コマンドはすべてsudo経由で実行されます

### 必要なパッケージを導入

	$ ./builder.sh apt

### rootfsの構築

	$ ./builder.sh rootfs

### セットアップ

	$ ./builder.sh setup
	
### インストール

/dev/sdXへインストール **指定したディスクの元の内容は全て消えます!**

	$ ./builder.sh install /dev/sdX

# 参考文献

[cdebootstrap で Raspberry Pi 4 用 Debian Buster arm64 環境を作る](https://www.manabii.info/2020/05/making-debian-bister-arm64-64bit-for-raspberry-pi-by-cdebootstrap.html)
