#! /bin/sh
# Copyright 2016 Philippe Mariman
# MIT License

# NOTE: script dependencies: debootstrap qemu qemu-user-static binfmt-support fakeroot


print_help () {
cat << EOF
${SCRIPT_NAME} - builds a debian based armhf root file system using debootstrap
Usage: ${SCRIPT_NAME} [OPTIONS]

Options:
-b, --base              base directory where to create the build directory
-n, --name              name of the root build directory
-p, --password PASSWD   root password, default "root"
-i, --include FILE      include file containing list of additional pkgs (one per line)
-o, --overlay DIR       path to overlay directory, which will be copied over to the root
-r, --repo URI          set repository:
                        * "rpi" (Raspbian repository,default)
                        * "deb" (official Debian armhf repository)
                        * "http://custom-repo.com/dir" (custom repo)
-d. --dry-run           prints debootstrap command (first stage) and exits
-v, --version           prints version of script
-h, --help              prints this help text
EOF
}


exit_script () {
        [ -n "$1" ] && [ $1 -gt 0 ] && exit 1
        exit 0
}


target_overlay () {
        [ -z "$1" ] && return 1
        [ -z "$2" ] && return 0
        local TARGET_DIR=$1
        local OVERLAY_DIR=$2
        if [ -d "${OVERLAY_DIR}" ] ; then
                # copy overlay directory (/etc files for example)
                fakeroot cp -r ${OVERLAY_DIR}/* ${TARGET_DIR}/
        fi
        return 0
}


target_image_stamp () {
        [ -z "$1" ] && return 1
        # make stamp file
        echo "script-name:${SCRIPT_NAME} [ver ${SCRIPT_VERSION}]" > $1
        echo "user@system:${BUILD_USER}@"$(cat /etc/hostname) >> $1
        echo "timestamp:"$(date +%Y%m%d-%H%M%S) >> $1
        echo "repository:${DEBOOTSTRAP_ARCHIVE}" >> $1
        echo "suite:${DEBOOTSTRAP_SUITE}" >> $1
        echo "build-id:${DEBOOTSTRAP_ID}" >> $1
        return 0
}


pkg_include () {
        [ -z "$1" ] && return 0
        local incfile=$1

        if [ ! -e $incfile ] ; then
                return 1
        fi

        # loop over packages file
        while read pkg; do
                case "$pkg" in \#*) continue ;; esac
                if [ -z "${DEBOOTSTRAP_INCLUDE}" ] ; then
                        DEBOOTSTRAP_INCLUDE="$pkg"
                else
                        DEBOOTSTRAP_INCLUDE="${DEBOOTSTRAP_INCLUDE},$pkg"
                fi
        done < $incfile

        return 0
}


debootstrap_second_stage () {
        local TARGET_DIR=$1
        local TARGET_PASSWD=$2

        [ -z "${TARGET_DIR}" -o ! -d ${TARGET_DIR} ] && return 1
        [ -z "${TARGET_PASSWD}" ] && TARGET_PASSWD=root
        
        local TARGET_PASSWD_FILE=${TARGET_DIR}/password
        local BIN_CHROOT=/usr/sbin/chroot
        local BIN_QEMU=/usr/bin/qemu-arm-static

        # copy qemu-static
        cp ${BIN_QEMU} ${TARGET_DIR}/usr/bin/

        # chroot into target image for second stage
        ${BIN_CHROOT} ${TARGET_DIR} /debootstrap/debootstrap --second-stage

        # set root password
        echo "root:${TARGET_PASSWD}" > ${TARGET_PASSWD_FILE}
        ${BIN_CHROOT} ${TARGET_DIR} chpasswd < ${TARGET_PASSWD_FILE}
        rm ${TARGET_PASSWD_FILE}

        # set timezone (currently hard-coded to GMT+1)
        echo 'Europe/Brussels' > ${TARGET_DIR}/etc/timezone
        ${BIN_CHROOT} ${TARGET_DIR} dpkg-reconfigure --frontend noninteractive tzdata

        # make link for vim to vim.tiny
        ${BIN_CHROOT} ${TARGET_DIR} ln -sf /usr/bin/vim.tiny /usr/bin/vim

        # clean up
        ${BIN_CHROOT} ${TARGET_DIR} apt-get clean
        ${BIN_CHROOT} ${TARGET_DIR} apt-get autoclean
        rm -f ${TARGET_DIR}${BIN_QEMU}

        return 0
}


set_image_repository () {
        # select repository
        case $SCRIPT_REPO in
                rpi)
                        DEBOOTSTRAP_ARCHIVE=http://archive.raspbian.org/raspbian/
                        ;;
                deb)
                        DEBOOTSTRAP_ARCHIVE=http://ftp.be.debian.org/debian/
                        ;;
                *)
                        DEBOOTSTRAP_ARCHIVE="$SCRIPT_REPO"
                        ;;
        esac
}


parse_opts () {
        while [ -n "$1" ]
        do
                case $1 in
                -p|--password)
                        SCRIPT_PASSWD=$2
                        shift 2
                        ;;
                -b|--base)
                        BUILD_BASE=$2
                        shift 2
                        ;;
                -n|--name)
                        BUILD_VERSION=$2
                        shift 2
                        ;;
                -i|--include)
                        SCRIPT_INC_FILE=$2
                        shift 2
                        ;;
                -o|--overlay)
                        TARGET_OVERLAY=$2
                        shift 2
                        ;;
                -r|--repo)
                        SCRIPT_REPO=$2
                        shift 2
                        ;;
                -d|--dry-run)
                        SCRIPT_DRYRUN=y
                        shift 1
                        ;;
                -v|--version)
                        echo "${SCRIPT_NAME} - version ${SCRIPT_VERSION}"
                        exit_script
                        ;;
                -h|--help)
                        print_help
                        exit_script
                        ;;
                *)
                        print_help
                        exit_script 1
                        ;;
                esac
        done
}


# start of script

SCRIPT_VERSION=2.0
SCRIPT_NAME=$(basename $0)
SCRIPT_DRYRUN=n
SCRIPT_REPO=deb
SCRIPT_INC_FILE=

parse_opts $@

if [ ${USER} != "root" ] ; then
        echo "run as root"
        exit_script 1
fi

if [ -n ${SUDO_USER} ] ; then
        BUILD_USER=${SUDO_USER}
else
        BUILD_USER=${USER}
fi

# check destination of build dir
[ -z "${BUILD_BASE}" ] && BUILD_BASE=/opt/build
[ -z "${BUILD_VERSION}" ] && BUILD_VERSION=deb-jessie-build

if [ ! -d "${BUILD_BASE}" ] ; then
        echo "image base directory non existing"
        exit_script 1
fi

DEBOOTSTRAP_ID=${BUILD_VERSION}
DEBOOTSTRAP_SUITE=jessie
#DEBOOTSTRAP_VARIANT=minbase
DEBOOTSTRAP_VARIANT=
DEBOOTSTRAP_TARGET=${BUILD_BASE}"/"${BUILD_VERSION}
DEBOOTSTRAP_INCLUDE="vim-tiny,openssh-server"

set_image_repository

pkg_include $SCRIPT_INC_FILE

DEBOOTSTRAP_CMD="debootstrap --no-check-gpg --foreign --arch=armhf"

if [ -n "${DEBOOTSTRAP_VARIANT}" ] ; then
        DEBOOTSTRAP_CMD="${DEBOOTSTRAP_CMD} --variant=${DEBOOTSTRAP_VARIANT}"
fi

if [ -n "${DEBOOTSTRAP_INCLUDE}" ] ; then
        DEBOOTSTRAP_CMD="${DEBOOTSTRAP_CMD} --include=${DEBOOTSTRAP_INCLUDE}"
fi

DEBOOTSTRAP_CMD="${DEBOOTSTRAP_CMD} ${DEBOOTSTRAP_SUITE} ${DEBOOTSTRAP_TARGET} ${DEBOOTSTRAP_ARCHIVE}"

# check target dir
if [ -d "${DEBOOTSTRAP_TARGET}" ] ; then
        # remove existing target directory
        rm -rf ${DEBOOTSTRAP_TARGET}
fi

# check dry run
if [ "${SCRIPT_DRYRUN}" = "y" ] ; then
        echo ${DEBOOTSTRAP_CMD}
        exit_script
fi

# perform first stage debootstrap
${DEBOOTSTRAP_CMD}
if [ $? -ne 0 ] ; then
        echo "error debootstrap first stage"
        exit_script 1
fi

debootstrap_second_stage ${DEBOOTSTRAP_TARGET} ${SCRIPT_PASSWD}
if [ $? -ne 0 ] ; then
        echo "error debootstrap second stage"
        exit_script 1
fi

target_overlay ${DEBOOTSTRAP_TARGET} ${TARGET_OVERLAY}

target_image_stamp ${DEBOOTSTRAP_TARGET}/etc/image-release

exit_script
