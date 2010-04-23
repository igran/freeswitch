#
#
#
EAPI="2"

inherit linux-mod

MY_P="${PN}-${PV/_p/.}b"
DESCRIPTION="Wanpipe driver for Sangoma PCI/PCIe Telephony Cards"
HOMEPAGE="http://www.sangoma.com/"
SRC_URI="ftp://ftp.sangoma.com/linux/custom/DavidYS/${MY_P}.tgz"

IUSE="+dahdi"
KEYWORDS="~x86"
LICENSE=""
SLOT="0"

RDEPEND="dahdi? ( net-misc/dahdi )"
DEPEND="${RDEPEND}"

S="${WORKDIR}/${P/_p/.}"
S_DAHDI="${WORKDIR}/dahdi"
S_KERNEL="${WORKDIR}/kernel"

#pkg_setup() {
#	linux-mod_pkg_setup
#}

src_prepare() {
	###
	# DAHDI: copy includes
	#
	if use dahdi; then
		mkdir -p "${S_DAHDI}"/{include,drivers/dahdi} || die "Failed to create directory for dahdi includes"
		cp -R "${ROOT}/usr/include/dahdi" "${S_DAHDI}/include" || die "Failed to copy dahdi headers"

		if linux_chkconfig_builtin MODVERSIONS; then
			# extract symbol version
			/bin/sh "${FILESDIR}/extract_symver.sh" \
				"/lib/modules/${KV_FULL}/dahdi" > "${S_DAHDI}/drivers/dahdi/Module.symvers" || die "Failed to extract dahdi modules symbol version"
		else
			# shut up bogus wanpipe error message and modpost warnings,
			# create a fake Module.symvers for dahdi.ko
			#
			cat - >"${S_DAHDI}/drivers/dahdi/Module.symvers" <<-EOF
			0x00000000	dahdi_rbsbits	dahdi/dahdi	EXPORT_SYMBOL_GPL
			0x00000000	dahdi_ec_chunk	dahdi/dahdi	EXPORT_SYMBOL_GPL
			0x00000000	dahdi_alarm_channel	dahdi/dahdi	EXPORT_SYMBOL_GPL
			0x00000000	dahdi_unregister	dahdi/dahdi	EXPORT_SYMBOL_GPL
			0x00000000	dahdi_ec_span	dahdi/dahdi	EXPORT_SYMBOL_GPL
			0x00000000	dahdi_receive	dahdi/dahdi	EXPORT_SYMBOL_GPL
			0x00000000	dahdi_hooksig	dahdi/dahdi	EXPORT_SYMBOL_GPL
			0x00000000	dahdi_qevent_lock	dahdi/dahdi	EXPORT_SYMBOL_GPL
			0x00000000	dahdi_register	dahdi/dahdi	EXPORT_SYMBOL_GPL
			0x00000000	dahdi_transmit	dahdi/dahdi	EXPORT_SYMBOL_GPL
			0x00000000	dahdi_hdlc_getbuf	dahdi/dahdi	EXPORT_SYMBOL_GPL
			0x00000000	dahdi_alarm_notify	dahdi/dahdi	EXPORT_SYMBOL_GPL
			EOF
		fi
	fi

	###
	# Kernel: create a local copy, so wanpipe doesn't
	#         mess up things in /usr/src/...
	#
	# Credits: based on the wanpipe-3.1.4 ebuild in http://bugs.gentoo.org/show_bug.cgi?id=188939
	#
	mkdir -p "${S_KERNEL}" || die "Failed to create create ${S_KERNEL}"
	cp -dPR "${KERNEL_DIR}/include" "${S_KERNEL}" || die "Failed to copy ${KV_FULL} includes to ${S_KERNEL}"
	ln -s "${KERNEL_DIR}/Makefile"  "${S_KERNEL}/Makefile" || die "Failed to symlink ${KV_FULL} Makefile"
	ln -s "${KERNEL_DIR}/scripts"   "${S_KERNEL}/scripts"  || die "Failed to symlink ${KV_FULL} scripts"
	ln -s "${KERNEL_DIR}/arch"      "${S_KERNEL}/arch"     || die "Failed to symlink ${KV_FULL} arch"
	ln -s "${KERNEL_DIR}/.config"   "${S_KERNEL}/.config"  || die "Failed to symlink ${KV_FULL} .config"

	[ -f "${KERNEL_DIR}/Module.symvers" ] && \
		ln -s "${KERNEL_DIR}/Module.symvers" "${S_KERNEL}/Module.symvers"

	# Remove kernel's (old) wanrouter.h,
	# so we're really only using wanpipe's version
	#
	rm -f "${S_KERNEL}/include/linux/wanrouter.h" || die "Failed to remove ${KV_FULL} old linux/wanrouter.h"

	###
	# Wanpipe: disable header cleaning script,
	#          disable depmod call
	#          do not install headers during "make all_util"
	#
	epatch "${FILESDIR}/${P/11/10_p10}-Makefile.patch"

	# Silence memset/memcpy implicit declaration QA warnings
	epatch "${FILESDIR}/${P/11*/10}-silence-QA-warnings.patch"

	# Silence "jobserver unavailable" messages and QA warnings
	epatch "${FILESDIR}/${P/11*/10}-QA-fix-parallel-make.patch"

	# TODO: Silence "stel_tone/fsk.c:240: warning: dereferencing type-punned pointer will break strict-aliasing rules"
	#epatch "${FILESDIR}/${P/11*/10}-QA-fix-libstelephony.patch"

	# Silence gcc-4.4 "warning: format not a string literal and no format arguments"
	epatch "${FILESDIR}/${P/11*/10}-QA-fix-format-literal-warnings.patch"

	# Silence gcc-4.4 "warning: deprecated conversion from string constant to 'char*'"
	epatch "${FILESDIR}/${P/11*/10}-QA-fix-const-char-warnings.patch"

	# >=2.6.31
#	if kernel_is -ge 2 6 31 ; then
#		epatch "${FILESDIR}"/${P/_p*}-linux-2.6.31.patch
#	fi

#	# Remove some include paths
#	sed -i -e "s:-I\$(INSTALLPREFIX)/include::; s:-I\$(INSTALLPREFIX)/usr/include::" \
#		Makefile
}

src_compile() {
	# DEBUG: deny write access to linux source
	addread "${KERNEL_DIR}"

	# Build everything
	emake all_src all_lib ARCH="$(tc-arch-kernel)" DAHDI_DIR="${S_DAHDI}" KVER="${KV_FULL}" KDIR="${S_KERNEL}" DESTDIR="${D}" || "Failed to build wanpipe"
}

src_install() {
	# install drivers, tools, headers and libs
	emake install install_lib ARCH="$(tc-arch-kernel)" KVER="${KV_FULL}" KDIR="${S_KERNEL}" DESTDIR="${D}" || die "Failed to install wanpipe"

	# remove bogus symlink
	rm "${D}/usr/include/wanpipe/linux"

	# remove trixbox setup script
	rm -r "${D}/usr/local"

	# fixup permissions
	find "${D}/usr/include/wanpipe" -type f -exec chmod 644 {} \;

	# empty, but used by wanpipe/-router scripts
	keepdir /etc/wanpipe/{interfaces,scripts}

	# remove duplicate wan_aftup binary from /etc/wanpipe...
	# TODO: fixup Makefile
	sed -i -e 's:\(\./\)\?wan_aftup:/usr/sbin/wan_aftup:g' \
		"${D}/etc/wanpipe/util/wan_aftup/update_aft_firm.sh" || die "Failed to update update_aft_firm.sh"
	rm "${D}/etc/wanpipe/util/wan_aftup/wan_aftup"

	# find leftover files in /etc/wanpipe
	find "${D}/etc/wanpipe" -type f -iname "Makefile" -exec rm {} \;

	# clean up /etc/wanpipe/wancfg_zaptel
	# (all these are already in /usr/sbin or useless)
	for x in setup-sangoma wancfg_{zaptel,dahdi,tdmapi,openzap,fs,smg,hp_tdmapi} {clean,install,uninstall}.sh; do
		rm "${D}/etc/wanpipe/wancfg_zaptel/${x}" || die "Failed to remove /etc/wanpipe/wancfg_zaptel/${x}"
	done

	# move samples to /usr/share/doc/...
	dodir "/usr/share/doc/${PF}"
	rm "${D}/etc/wanpipe/samples/clean.sh"
	mv "${D}/etc/wanpipe/samples" "${D}/usr/share/doc/${PF}" || die "Failed to move samples to /usr/share/doc/${PF}"
}
