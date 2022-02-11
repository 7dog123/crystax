#!/usr/bin/env bash

version=10.3.2
srcdir=/tmp/crystax-ndk-sources-$USER
incremental=yes
verbose=yes
git_fetch=autodetect

usage()
{
    echo "Usage: $0 [parameters]"
    echo ""
    echo "Common parameters:"
    echo ""
    echo "  -h,--help                Show this screen and exit"
    echo "  -v,--[no-]verbose        Enable verbose mode [$verbose]"
    echo ""
    echo "Optional parameters:"
    echo ""
    echo "  -s,--srcdir=PATH         Path to the sources directory"
    echo "                           [$srcdir]"
    echo ""
    echo "  -i,--[no-]incremental    Enable incremental build [$incremental]"
    echo ""
    echo "  -f,--[no-]git-fetch      Fetch git repositories [$git_fetch]"
    echo ""
}

opt_srcdir=

while [ -n "$1" ]; do
    arg=$1
    argval=$(expr "x$arg" : "^x--[^=]*=\(.*\)$")
    shift

    case $arg in
        -h|-help|--help)
            usage
            exit 0
            ;;
        -v|--verbose)
            verbose=yes
            ;;
        --no-verbose)
            verbose=no
            ;;
        -s|--srcdir)
            opt_srcdir="$1"
            shift
            ;;
        --srcdir=*)
            opt_srcdir="$argval"
            ;;
        -i|--incremental)
            incremental=yes
            ;;
        --no-incremental)
            incremental=no
            ;;
        -f|--git-fetch)
            git_fetch=yes
            ;;
        --no-git-fetch)
            git_fetch=no
            ;;
        -*)
            usage 1>&2
            exit 1
            ;;
        *)
            if [ -z "$opt_srcdir" ]; then
                opt_srcdir=$arg
            else
                usage 1>&2
                exit 1
            fi
    esac
done

test -n "$opt_srcdir" && srcdir="$opt_srcdir"

if [ "$verbose" = "yes" ]; then
    echo "=== Sources directory: $srcdir"
    echo "=== Incremental build: $incremental"
fi

repositories()
{
    local reps="\
        platform/bionic \
        platform/development \
        platform/ndk \
        platform/prebuilts/rs \
        platform/prebuilts/tools \
        platform/system/core \
        toolchain/binutils \
        toolchain/build \
        toolchain/cloog \
        toolchain/expat \
        toolchain/gcc/gcc-4.9 \
        toolchain/gcc/gcc-5 \
        toolchain/gdb/gdb-7.10 \
        toolchain/gmp \
        toolchain/isl \
        toolchain/libedit \
        toolchain/llvm-3.6/clang \
        toolchain/llvm-3.6/compiler-rt \
        toolchain/llvm-3.6/libcxx \
        toolchain/llvm-3.6/libcxxabi \
        toolchain/llvm-3.6/lldb \
        toolchain/llvm-3.6/llvm \
        toolchain/llvm-3.7/clang \
        toolchain/llvm-3.7/compiler-rt \
        toolchain/llvm-3.7/libcxx \
        toolchain/llvm-3.7/libcxxabi \
        toolchain/llvm-3.7/lldb \
        toolchain/llvm-3.7/llvm \
        toolchain/mclinker \
        toolchain/mpc \
        toolchain/mpfr \
        toolchain/perl \
        toolchain/ppl \
        toolchain/python \
        toolchain/sed \
        toolchain/yasm \
        vendor/boost/1.59.0 \
        vendor/cocotron \
        vendor/dlmalloc \
        vendor/freebsd \
        vendor/icu \
        vendor/libdispatch \
        vendor/libjpeg \
        vendor/libjpeg-turbo \
        vendor/libkqueue \
        vendor/libobjc2 \
        vendor/libpng \
        vendor/libpwq \
        vendor/libtiff \
        vendor/openpts \
        vendor/python/python-2.7 \
        vendor/python/python-3.5 \
        vendor/sqlite3 \
        "

    local host_os=$(uname -s | tr '[A-Z]' '[a-z]')
    case $host_os in
        linux)
            reps="$reps \
                platform/prebuilts/gcc/linux-x86/host/i686-w64-mingw32-4.8 \
                platform/prebuilts/gcc/linux-x86/host/x86_64-linux-glibc2.11-4.8 \
                platform/prebuilts/gcc/linux-x86/host/x86_64-w64-mingw32-4.8 \
                "
            ;;
        darwin)
            reps="$reps\
                platform/prebuilts/clang/darwin-x86/host/x86_64-apple-darwin-3.7.0 \
                platform/prebuilts/gcc/darwin-x86/host/x86_64-apple-darwin-4.9.3 \
                "
            ;;
        *)
            echo "ERROR: Unsupported OS: '$host_os'" 1>&2
            exit 1
    esac

    echo $reps | tr ' ' '\n' | sort | tr '\n' ' '
}

run()
{
    if [ "$verbose" = "yes" ]; then
        echo "## COMMAND: $@"
    fi
    "$@"
}

githubname()
{
    local repname=$1
    if [ -z "$repname" ]; then
        echo "INTERNAL ERROR: empty repository passed to githubname" 1>&2
        exit 1
    fi

    local name
    local rversion
    case $repname in
        toolchain/llvm-*)
            rversion=$(dirname $repname | sed 's/^[^\-]*-\(.*\)$/\1/')
            name=toolchain/$(basename $repname)-${rversion}
            ;;
        toolchain/gcc/gcc-*)
            rversion=$(basename $repname | sed 's/^[^\-]*-\(.*\)$/\1/')
            name=toolchain/gcc-${rversion}
            ;;
        toolchain/gdb/gdb-*)
            rversion=$(basename $repname | sed 's/^[^\-]*-\(.*\)$/\1/')
            name=toolchain/gdb-${rversion}
            ;;
        vendor/python/python-*)
            rversion=$(basename $repname | sed 's/^[^\-]*-\(.*\)$/\1/')
            name=vendor/python-${rversion}
            ;;
        *)
            name=$repname
    esac

    echo https://github.com/crystax/android-$(echo $name | tr '/' '-' | tr '.' '-')
}

fetch_git_repositories()
{
    local srcdir=$1
    if [ -z "$srcdir" ]; then
        echo "INTERNAL ERROR: empty dir passed to 'fetch'" 1>&2
        exit 1
    fi

    local reps=$(repositories)

    if [ "$git_fetch" = "autodetect" ]; then
        git_fetch=no
        for r in $reps; do
            if [ -e $srcdir/$r/.git ]; then
                continue
            fi
            git_fetch=yes
            break
        done
    fi

    if [ "$git_fetch" != "yes" ]; then
        return 0
    fi

    for r in $reps; do
        echo "=== Fetching $r ..."
        if [ ! -d $srcdir/$r ]; then
            run mkdir -p $srcdir/$r || return 1
            ( cd $srcdir/$r && run git init ) || return 1
        fi
        (
            cd $srcdir/$r || exit 1
            run git config remote.origin.url $(githubname $r) || exit 1
            run git config remote.origin.fetch '+refs/heads/*:refs/remotes/origin/*' || exit 1
            run git fetch --prune origin || exit 1
            run git reset --hard || exit 1
            run git clean -fddx || exit 1
            run git checkout crystax-ndk-$version || exit 1
        ) || return 1
    done
}

mkdir -p $srcdir || exit 1
cd $srcdir || exit 1
srcdir=$(pwd)

fetch_git_repositories $srcdir || exit 1

cd $srcdir/platform/ndk || exit 1

if [ "$incremental" = "yes" ]; then
    echo "=== Use cache /var/tmp/ndk-cache-$USER"
    for f in $(ls -1 /var/tmp/ndk-cache-$USER/*.tar.xz 2>/dev/null); do
        echo "=== Unpack ${f} ..."
        run tar xf $f || exit 1
    done
else
    echo "=== Cleanup cache /var/tmp/ndk-cache-$USER ..."
    run rm -Rf /var/tmp/ndk-cache-$USER || exit 1
fi

echo "=== Cleanup build directory /tmp/ndk-$USER ..."
run rm -Rf /tmp/ndk-$USER || exit 1

export ANDROID_NDK_ROOT=$srcdir/platform/ndk
export NDK_LOGFILE=/tmp/ndk-$USER/build.log

echo "=== Building CrystaX NDK ..."
run ./build/tools/make-release.sh \
    --verbose \
    --force \
    --also-64 \
    --prefix=crystax-ndk \
    --release=$version \
    --toolchain-src-dir=$srcdir/toolchain \
    || exit 1

exit 0
