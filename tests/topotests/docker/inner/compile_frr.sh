#!/bin/bash
#
# Copyright 2018 Network Device Education Foundation, Inc. ("NetDEF")
#
# Permission is hereby granted, free of charge, to any person obtaining
# a copy of this software and associated documentation files (the
# "Software"), to deal in the Software without restriction, including
# without limitation the rights to use, copy, modify, merge, publish,
# distribute, sublicense, and/or sell copies of the Software, and to
# permit persons to whom the Software is furnished to do so, subject to
# the following conditions:
#
# The above copyright notice and this permission notice shall be
# included in all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
# EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
# MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
# NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS
# BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN
# ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
# CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.

set -e

# Load shared functions
CDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. $CDIR/funcs.sh

#
# Script begin
#

if [ "${TOPOTEST_CLEAN}" != "0" ]; then
	log_info "Cleaning FRR builddir..."
	rm -rf $FRR_SYNC_DIR $FRR_BUILD_DIR &> /dev/null
fi

log_info "Syncing FRR source with host..."
mkdir -p $FRR_SYNC_DIR
rsync -a --info=progress2 \
	--exclude '*.o' \
	--exclude '*.lo'\
	--chown root:root \
	$FRR_HOST_DIR/. $FRR_SYNC_DIR/
(cd $FRR_SYNC_DIR && git clean -xdf > /dev/null)
mkdir -p $FRR_BUILD_DIR
rsync -a --info=progress2 --chown root:root $FRR_SYNC_DIR/. $FRR_BUILD_DIR/

cd "$FRR_BUILD_DIR" || \
	log_fatal "failed to find frr directory"

if [ "${TOPOTEST_VERBOSE}" != "0" ]; then
	exec 3>&1
else
	exec 3>/dev/null
fi

log_info "Building FRR..."

if [ ! -e configure ]; then
	bash bootstrap.sh >&3 || \
		log_fatal "failed to bootstrap configuration"
fi

if [ "${TOPOTEST_DOC}" != "0" ]; then
	EXTRA_CONFIGURE+=" --enable-doc "
else
	EXTRA_CONFIGURE+=" --disable-doc "
fi

if [ ! -e Makefile ]; then
	if [ "${TOPOTEST_SANITIZER}" != "0" ]; then
		export CC="gcc"
		export CFLAGS="-O1 -g -fsanitize=address -fno-omit-frame-pointer"
		export LDFLAGS="-g -fsanitize=address -ldl"
		touch .address_sanitizer
	else
		rm -f .address_sanitizer
	fi

	bash configure >&3 \
		--enable-static-bin \
		--enable-static \
		--enable-shared \
		--with-moduledir=/usr/lib/frr/modules \
		--prefix=/usr \
		--localstatedir=/var/run/frr \
		--sbindir=/usr/lib/frr \
		--sysconfdir=/etc/frr \
		--enable-multipath=0 \
		--enable-fpm \
		--enable-sharpd \
		$EXTRA_CONFIGURE \
		--with-pkg-extra-version=-topotests \
		|| log_fatal "failed to configure the sources"
fi

# if '.address_sanitizer' file exists it means we are using address sanitizer.
if [ -f .address_sanitizer ]; then
	make -C lib CFLAGS="-g -O2" LDFLAGS="-g" clippy >&3
fi

make -j$(cpu_count) >&3 || \
	log_fatal "failed to build the sources"

make install >/dev/null || \
	log_fatal "failed to install frr"