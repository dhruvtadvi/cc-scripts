BLEEDING=1
CWD=$(pwd)
BINUTILSV=
GCCV=
GLIBCV=
LAPIV=
FLAGS="-O3"
JOBS=$(nproc --all)
PREFIX=$CWD/out
export PATH=$PATH:$PREFIX/bin
TARGET=aarch64-linux-gnu

releases_source_urls=(
	"https://ftp.gnu.org/gnu/binutils/binutils-2.42.tar.gz" 2.42 \
		"http://mirror.koddos.net/gcc/releases/gcc-13.2.0/gcc-13.2.0.tar.gz" 13.2.0 \
		"https://ftp.gnu.org/gnu/glibc/glibc-2.39.tar.gz" "2.39"
	)

KERNEL_SOURCE="https://cdn.kernel.org/pub/linux/kernel/v6.x/linux-6.7.4.tar.xz"
repo_source_urls=(
	"https://sourceware.org/git/binutils-gdb.git" \
		"https://gcc.gnu.org/git/gcc.git" \
		"https://sourceware.org/git/glibc.git"
	)

download_sources() {
    if [ $BLEEDING -eq 0 ]; then
	for url version in $releases_source_urls[@]; do 
	    file_name=$(basename $url)
	    first_name=$(echo $file_name | awk -F"-" '{print $1}')
	    if [ ! -f $file_name ]; then
		wget $url -O $file_name
		echo "extracting $file_name"
		mkdir $first_name
		tar -xf $file_name -C $first_name --strip-components 1
	    fi
	done
    else 
	for url in $repo_source_urls[@]; do
	    file_name=$(basename $url .git)
	    first_name=$(echo $file_name | awk -F"-" '{print $1}')
	    if [ ! -d "$file_name" ]; then
		git clone $url --depth=1
	    fi
	done
    fi
    if [ ! -f $(basename $KERNEL_SOURCE) ]; then
	wget $KERNEL_SOURCE
	mkdir linux
	tar -xf $(basename $KERNEL_SOURCE) -C linux --strip-components 1
    fi
}

build_binutils() {
	cd binutils > /dev/null 2>&1 || cd binutils-gdb > /dev/null 2>&1
	if [ -d build ]; then rm -rf build;fi
	mkdir build
	cd build

	../configure CFLGAGS=$FLAGS CXXFLAGS=$FLAGS \
		--prefix=$PREFIX \
		--target=$TARGET \
		--enable-gdb

	make -j$JOBS
	make install
	cd ../..
}

setup_kernel_headers() {
	cd linux
	make ARCH=arm64 INSTALL_HDR_PATH=$PREFIX/$TARGET headers_install
	mkdir $PREFIX/$TARGET/usr
	ln -sr $PREFIX/$TARGET/include $PREFIX/$TARGET/usr/include
	cd ..
}

build_gcc() {
	cd gcc
	sh contrib/download_prerequisites
	if [ -d build ]; then rm -rf build;fi
	mkdir build
	cd build
	
	../configure CFLGAGS=$FLAGS CXXFLAGS=$FLAGS \
		--disable-libsanitizer \
		--prefix=$PREFIX \
		--target=$TARGET \
		--includedir=$PREFIX/$TARGET/include \
		--enable-languages=c,c++

	make all-gcc -j$JOBS
	make install-gcc
	cd ../..
}

build_glibc() {
	cd glibc
	if [ -d build ]; then rm -rf build;fi
	mkdir build
	cd build

	../configure CFLAGS=$FLAGS CXXFLAGS=$FLAGS \
		--prefix=$PREFIX/$TARGET \
		--build=$MACHTYPE \
		--host=$TARGET \
		--target=$TARGET \
		--with-headers=$PREFIX/$TARGET/include \
		libc_cv_forced_unwind=yes

	make install-bootstrap-headers=yes install-headers
	make csu/subdir_lib -j$JOBS
	install csu/crt1.o csu/crti.o csu/crtn.o $PREFIX/$TARGET/lib
	$TARGET-gcc -nostdlib -nostartfiles -shared -x c /dev/null -o $PREFIX/$TARGET/lib/libc.so
	touch $PREFIX/$TARGET/include/gnu/stubs.h
	cd ../..

	cd gcc/build
	make all-target-libgcc -j$JOBS
	make install-target-libgcc
	cd ../..

	cd glibc/build
	make -j$JOBS
	make install
	cd ../..

	cd gcc/build
	make -j$JOBS
	make install
	cd ../..
}

#i'm expecting the version of the binutils with the gas configration
get_version_info() {
    cd binutils > /dev/null 2>&1 || cd binutils-gdb > /dev/null 2>&1
    BINUTILSV=$(cat gas/configure | grep PACKAGE_VERSION | head -n 1 | grep -oP "\d+\.\d+\.\d+")
    cd ..

    GCCV=$(cat gcc/gcc/BASE-VER)
    GLIBCV=$(cat glibc/version.h | grep -oP "\d+\.\d+\.\d+")

    cd linux
    LAPIV=$(make kernelversion)
    cd ..
}

download_sources
get_version_info
build_binutils
setup_kernel_headers
build_gcc
build_glibc


