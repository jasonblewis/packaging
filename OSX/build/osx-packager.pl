#!/usr/bin/perl

### = file
### osx-packager.pl
###
### = revision
### $Id$
###
### = location
### https://github.com/MythTV/packaging/raw/master/OSX/build/osx-packager.pl
###
### = description
### Tool for automating frontend builds on Mac OS X.
### Run "osx-packager.pl -man" for full documentation.

use strict;
use Getopt::Long qw(:config auto_abbrev);
use Pod::Usage ();
use Cwd ();

### Configuration settings (stuff that might change more often)

# We try to auto-locate the Git client binaries.
# If they are not in your path, we build them from source
#
our $git = `which git`; chomp $git;

# This script used to always delete the installed include and lib dirs.
# That probably ensures a safe build, but when rebuilding adds minutes to
# the total build time, and prevents us skipping some parts of a full build
#
our $cleanLibs = 1;

# By default, only the frontend is built (i.e. no backend or transcoding)
#
our $backend = 0;
our $jobtools = 0;

# Parallel makes?
#
#$ENV{'DISTCC_HOSTS'}   = "localhost 192.168.0.6";
#$ENV{'DISTCC_VERBOSE'} = '1';

# Start with a generic address and let sourceforge
# figure out which mirror is closest to us.
#
our $sourceforge = 'http://downloads.sourceforge.net';

# At the moment, there is mythtv plus...
our @components = ( 'mythplugins' );

# The OS X programs that we are likely to be interested in.
our @targets   = ( 'MythFrontend', 'MythAVTest',  'MythWelcome' );
our @targetsJT = ( 'MythCommFlag', 'MythJobQueue');
our @targetsBE = ( 'MythBackend',  'MythFillDatabase', 'MythTV-Setup');


# Patches for MythTV source
our %patches = ();

our %build_profile = (
  'master'
   => [
    'branch' => 'master',
    'mythtv'
    => [
        'ccache',
        'dvdcss',
        'freetype',
        'lame',
        'mysqlclient',
        #'dbus',
        'qt-git',
        'yasm',
       ],
    'mythplugins'
    => [
        'exif',
# MythMusic needs these:
        'taglib',
        'libogg',
        'vorbis',
        'flac',
       ],
     ],
  '0.24-fixes'
  => [
    'branch' => 'fixes/0.24',
    'mythtv'
    =>  [
        'ccache',
        'dvdcss',
        'freetype',
        'lame',
        'mysqlclient',
        #'dbus',
        'qt-git',
        'yasm',
      ],
    'mythplugins'
    =>  [
        'exif',
# MythMusic needs these:
        'taglib',
        'libogg',
        'vorbis',
        'flac',
      ],
    ],
);

our %depend = (

  'git' =>
  {
    'url' => 'http://www.kernel.org/pub/software/scm/git/git-1.7.3.4.tar.bz2',
  },

  'freetype' =>
  {
    'url' => "$sourceforge/sourceforge/freetype/freetype-2.1.10.tar.gz",
  },

  'lame' =>
  {
    'url'
    =>  "$sourceforge/sourceforge/lame/lame-3.96.1.tar.gz",
    'conf'
    =>  [
          '--disable-frontend',
        ],
  },

  'libmad' =>
  {
    'url' => "$sourceforge/sourceforge/mad/libmad-0.15.0b.tar.gz"
  },

  'taglib' =>
  {
    'url' => 'http://developer.kde.org/~wheeler/files/src/taglib-1.6.3.tar.gz',
  },

  'libogg' =>
  {
    'url' => 'http://downloads.xiph.org/releases/ogg/libogg-1.1.2.tar.gz'
  },

  'vorbis' =>
  {
    'url' => 'http://downloads.xiph.org/releases/vorbis/libvorbis-1.1.1.tar.gz'
  },

  'flac' =>
  {
    'url' => "$sourceforge/sourceforge/flac/flac-1.1.4.tar.gz",
    # Workaround Intel problem - Missing _FLAC__lpc_restore_signal_asm_ia32
    'conf' => [ '--disable-asm-optimizations' ]
  },

  'dvdcss' =>
  {
    'url'
    =>  'http://download.videolan.org/pub/videolan/libdvdcss/1.2.9/libdvdcss-1.2.9.tar.bz2'
  },

  'mysqlclient' =>
  {
    'url'
    => 'http://downloads.mysql.com/archives/mysql-5.1/mysql-5.1.56.tar.gz',
    'conf'
    =>  [
          '--without-debug',
          '--without-docs',
          '--without-man',
          '--without-bench',
          '--without-server',
          '--without-geometry',
          '--without-extra-tools',
        ],
  },

  'dbus' =>
  {
    'url' => 'http://dbus.freedesktop.org/releases/dbus/dbus-1.0.3.tar.gz',
    'post-make' => 'mv $PREFIX/lib/dbus-1.0/include/dbus/dbus-arch-deps.h '.
                     ' $PREFIX/include/dbus-1.0/dbus ; '.
                   'rm -fr $PREFIX/lib/dbus-1.0 ; '.
                   'cd $PREFIX/bin ; '.
                   'echo "#!/bin/sh
if [ \"\$2\" = dbus-1 ]; then
  case \"\$1\" in
    \"--version\") echo 1.0.3  ;;
    \"--cflags\")  echo -I$PREFIX/include/dbus-1.0 ;;
    \"--libs\")    echo \"-L$PREFIX/lib -ldbus-1\" ;;
  esac
fi
exit 0"   > pkg-config ; '.
                   'chmod 755 pkg-config'
  },

  'qt-git' =>
  {
    'url'
    => '/Users/jason/qt',
    'url-type'
    => 'git',
   'conf-cmd'
    =>  'MAKEFLAGS=$parallel_make_flags ./configure',
    'conf'
    =>  [
         '-opensource',
         '-confirm-license',
          '-prefix', '"$PREFIX"',
          '-release',
          '-fast',
          '-no-accessibility',
          '-no-stl',
          # When MythTV all ported:  '-no-qt3support',

          # 10.7 and XCode 4.1 suggestion from Jean-Yves Avenard:
          '-sdk /Developer/SDKs/MacOSX10.6.sdk',
          # build for mac platform
          '-platform macx-g++-64',

          # When MySQL 5.1 is used, its plugin.h file clashes with Qt's.
          # To work around that, replace these three lines:
          # '-I"$PREFIX/include/mysql"',
          # '-L"$PREFIX/lib/mysql"',
          # '-qt-sql-mysql',
          # with:
          '-qt-sql-mysql -mysql_config "$PREFIX/bin/mysql_config"',

          '-no-sql-sqlite',
          '-no-sql-odbc',
          '-system-zlib',
          '-no-libtiff',
          '-no-libmng',
          '-nomake examples -nomake demos',
          '-no-nis',
          '-no-cups',
          '-no-qdbus',
          #'-dbus-linked',
          '-no-framework',
          '-no-multimedia',
          '-no-phonon',
          '-no-svg',
          '-no-javascript-jit',
          '-no-scripttools',
       ],
    'make'
    =>  [
          'sub-plugins-install_subtargets-ordered',
          'install_qmake',
          'install_mkspecs',
        ],
    # Using configure -release saves a lot of space and time,
    # but by default, debug builds of mythtv try to link against
    # debug libraries of Qt. This works around that:
    'post-make' => 'cd $PREFIX/lib ; '.
                   'ln -sf libQt3Support.dylib libQt3Support_debug.dylib ; '.
                   'ln -sf libQtSql.dylib      libQtSql_debug.dylib      ; '.
                   'ln -sf libQtXml.dylib      libQtXml_debug.dylib      ; '.
                   'ln -sf libQtOpenGL.dylib   libQtOpenGL_debug.dylib   ; '.
                   'ln -sf libQtGui.dylib      libQtGui_debug.dylib      ; '.
                   'ln -sf libQtNetwork.dylib  libQtNetwork_debug.dylib  ; '.
                   'ln -sf libQtCore.dylib     libQtCore_debug.dylib     ; '.
                   'ln -sf libQtWebKit.dylib   libQtWebKit_debug.dylib   ; '.
                   'ln -sf libQtScript.dylib   libQtScript_debug.dylib   ; '.
                   'rm -f $PREFIX/bin/pkg-config ; '.
                   '',
    'parallel-make' => 'yes'
  },
  'qt-4.6' =>
  {
    'url'
    => 'http://get.qt.nokia.com/qt/source/qt-everywhere-opensource-src-4.6.3.tar.gz',
    'conf-cmd'
    =>  'echo yes | MAKEFLAGS=$parallel_make_flags ./configure',
    'conf'
    =>  [
          '-opensource',
          '-prefix', '"$PREFIX"',
          '-release',
          '-fast',
          '-no-accessibility',
          '-no-stl',
          # When MythTV all ported:  '-no-qt3support',

          # 10.7 and XCode 4.1 suggestion from Jean-Yves Avenard:
          #'-sdk /Developer/SDKs/MacOSX10.6.sdk',


          # When MySQL 5.1 is used, its plugin.h file clashes with Qt's.
          # To work around that, replace these three lines:
          # '-I"$PREFIX/include/mysql"',
          # '-L"$PREFIX/lib/mysql"',
          # '-qt-sql-mysql',
          # with:
          '-qt-sql-mysql -mysql_config "$PREFIX/bin/mysql_config"',

          '-no-sql-sqlite',
          '-no-sql-odbc',
          '-system-zlib',
          '-no-libtiff',
          '-no-libmng',
          '-nomake examples -nomake demos',
          '-no-nis',
          '-no-cups',
          '-no-qdbus',
          #'-dbus-linked',
          '-no-framework',
          '-no-multimedia',
          '-no-phonon',
          '-no-svg',
          '-no-javascript-jit',
          '-no-scripttools',
       ],
    'make'
    =>  [
          'sub-plugins-install_subtargets-ordered',
          'install_qmake',
          'install_mkspecs',
        ],
    # Using configure -release saves a lot of space and time,
    # but by default, debug builds of mythtv try to link against
    # debug libraries of Qt. This works around that:
    'post-make' => 'cd $PREFIX/lib ; '.
                   'ln -sf libQt3Support.dylib libQt3Support_debug.dylib ; '.
                   'ln -sf libQtSql.dylib      libQtSql_debug.dylib      ; '.
                   'ln -sf libQtXml.dylib      libQtXml_debug.dylib      ; '.
                   'ln -sf libQtOpenGL.dylib   libQtOpenGL_debug.dylib   ; '.
                   'ln -sf libQtGui.dylib      libQtGui_debug.dylib      ; '.
                   'ln -sf libQtNetwork.dylib  libQtNetwork_debug.dylib  ; '.
                   'ln -sf libQtCore.dylib     libQtCore_debug.dylib     ; '.
                   'ln -sf libQtWebKit.dylib   libQtWebKit_debug.dylib   ; '.
                   'rm -f $PREFIX/bin/pkg-config ; '.
                   '',
    'parallel-make' => 'yes'
  }, # end qt-git

  'exif' =>
  {
    'url'  => "$sourceforge/sourceforge/libexif/libexif-0.6.17.tar.bz2",
    'conf' => [ '--disable-docs' ]
  },

  'yasm' =>
  {
    'url'  => 'http://www.tortall.net/projects/yasm/releases/yasm-1.1.0.tar.gz',
  },

  'ccache' =>
  {
    'url'  => 'http://samba.org/ftp/ccache/ccache-3.1.4.tar.bz2',
  },

);


=head1 NAME

osx-packager.pl - build OS X binary packages for MythTV

=head1 SYNOPSIS

 osx-packager.pl [options]

 Options:
   -help            print the usage message
   -man             print full documentation
   -verbose         print informative messages during the process
   -version <str>   custom version suffix (defaults to "gitYYYYMMDD")
   -noversion       don't use any version (for building release versions)
   -distclean       throw away all intermediate files and exit
   -thirdclean      do a clean rebuild of third party packages
   -thirdskip       don't rebuild the third party packages
   -mythtvskip      don't rebuild/install mythtv
   -pluginskip      don't rebuild/install mythplugins
   -clean           do a clean rebuild of MythTV
   -gitrev <str>    build a specified Git revision or tag, instead of HEAD
   -nohead          don't update to HEAD revision of MythTV before building
   -usehdimage      perform build inside of a case-sensitive disk image
   -leavehdimage    leave disk image mounted on exit
   -enable-backend  build the backend server as well as the frontend
   -enable-jobtools build commflag/jobqueue  as well as the frontend
   -profile         build with compile-type=profile
   -debug           build with compile-type=debug
   -m32             build for a 32-bit environment
   -plugins <str>   comma-separated list of plugins to include
   -srcdir  <path>  build using (fresh copy of) provided root mythtv directory
   -force           do not check for SVN validity
   -noclean         use with -nohead, do not re-run configure nor clean
   -config-only     quit after configuring mythtv

=head1 DESCRIPTION

This script builds a MythTV frontend and all necessary dependencies, along
with plugins as specified, as a standalone binary package for Mac OS X.

It was designed for building daily CVS, (then Subversion now Git) snapshots,
and can also be used to create release builds with the '-gitrev' option.

All intermediate files go into an '.osx-packager' directory in the current
working directory. The finished application is named 'MythFrontend.app' and
placed in the current working directory.

=head1 EXAMPLES

Building two snapshots, one with plugins and one without:

  osx-packager.pl -clean -plugins mythvideo,mythweather
  mv MythFrontend.app MythFrontend-plugins.app
  osx-packager.pl -nohead
  mv MythFrontend.app MythFrontend-noplugins.app

Building a "fixes" branch:

  osx-packager.pl -distclean
  osx-packager.pl -gitrev fixes/0.24

Note that this script will not build old branches.
Please try the branched version instead. e.g.
http://svn.mythtv.org/svn/branches/release-0-21-fixes/mythtv/contrib/OSX/osx-packager.pl

=head1 CREDITS

Written by Jeremiah Morris (jm@whpress.com)

Special thanks to Nigel Pearson, Jan Ornstedt, Angel Li, and Andre Pang
for help, code, and advice.

Small modifications made by Bas Hulsken (bhulsken@hotmail.com) to allow building current svn, and allow lirc (if installed properly on before running script). The modifications are crappy, and should probably be revised by someone who can actually code in perl. However it works for the moment, and I wanted to share with other mac frontend experimenters!

=cut

# Parse options
our (%OPT);
Getopt::Long::GetOptions(\%OPT,
                         'help|?',
                         'man',
                         'verbose',
                         'version=s',
                         'noversion',
                         'distclean',
                         'thirdclean',
                         'thirdskip',
                         'mythtvskip',
                         'pluginskip',
                         'clean',
                         'gitrev=s',
                         'nohead',
                         'usehdimage',
                         'leavehdimage',
                         'enable-backend',
                         'enable-jobtools',
                         'profile',
                         'debug',
                         'm32',
                         'plugins=s',
                         'srcdir=s',
                         'force',
                         'noclean',
			 'archives=s',
			 'buildprofile=s',
			 'config-only',
                        ) or Pod::Usage::pod2usage(2);
Pod::Usage::pod2usage(1) if $OPT{'help'};
Pod::Usage::pod2usage('-verbose' => 2) if $OPT{'man'};

if ( $OPT{'enable-backend'} )
{   $backend = 1  }

if ( $OPT{'clean'} )
{   $cleanLibs = 1  }

if ( $OPT{'noclean'} )
{   $cleanLibs = 0  }

if ( $OPT{'enable-jobtools'} )
{   $jobtools = 1  }

# Get version string sorted out
if ( $OPT{'gitrev'} && !$OPT{'version'} )
{
    $OPT{'version'} = $OPT{'gitrev'};
}
$OPT{'version'} = '' if $OPT{'noversion'};
unless (defined $OPT{'version'})
{
    my @lt = gmtime(time);
    $OPT{'version'} = sprintf('git%04d%02d%02d',
                              $lt[5] + 1900, $lt[4] + 1, $lt[3]);
}

if ( $OPT{'srcdir'} )
{
    $OPT{'nohead'} = 1;
    $OPT{'gitrev'} = '';
}

# Build our temp directories
our $SCRIPTDIR = Cwd::abs_path(Cwd::getcwd());
if ( $SCRIPTDIR =~ /\s/ )
{
    &Complain(<<END);
Working directory contains spaces

Error: Your current working path:

   $SCRIPTDIR

contains one or more spaces. This will break the compilation process,
so the script cannot continue. Please re-run this script from a different
directory (such as /tmp).

The application produced will run from any directory, the no-spaces
rule is only for the build process itself.

END
    die;
}

if ( $OPT{'nohead'} && ! $OPT{'force'} )
{
    my $GITTOP="$SCRIPTDIR/.osx-packager/src/myth-git/.git";

    if ( ! -d $GITTOP )
    {   die "No source code to build?"   }

    if ( ! `grep refs/heads/master $GITTOP/HEAD` )
    {   die "Source code does not match GIT master"   }
}
elsif ( $OPT{'gitrev'} =~ m,^fixes/, && $OPT{'gitrev'} lt "fixes/0.23" )
{
    &Complain(<<END);
This version of this script can not build old branches.
Please try the branched version instead. e.g.
http://svn.mythtv.org/svn/branches/release-0-23-fixes/packaging/OSX/build/osx-packager.pl
http://svn.mythtv.org/svn/branches/release-0-21-fixes/mythtv/contrib/OSX/osx-packager.pl
END
    die;
}


our $WORKDIR = "$SCRIPTDIR/.osx-packager";
mkdir $WORKDIR;

# Do we need to force a case-sensitive disk image?
if (0 &&       # No. MythTV source doesn't require it at the moment.
    !$OPT{usehdimage} && !CaseSensitiveFilesystem())
{
    Verbose("Forcing -usehdimage due to case-insensitive filesystem");
    $OPT{usehdimage} = 1;
}

if ($OPT{usehdimage})
{   MountHDImage()   }

our $PREFIX = "$WORKDIR/build";
mkdir $PREFIX;

our $SRCDIR = "$WORKDIR/src";
mkdir $SRCDIR;

our $ARCHIVEDIR ='';
if ( $OPT{'archives'} )
{
    $ARCHIVEDIR = "$SCRIPTDIR" . '/' . $OPT{'archives'};
} else {
    $ARCHIVEDIR = "$SRCDIR";
}

our %depend_order = '';
my $gitrevision = 'master';  # Default thingy to checkout
if ( $OPT{'buildprofile'} && $OPT{'buildprofile'} == '0.24-fixes' )
{
    Verbose('Building using 0.24-fixes profile');
    %depend_order = @{ $build_profile{'0.24-fixes'} };
    $gitrevision = 'fixes/0.24'
} else {
    Verbose('Building using master profile');
    %depend_order = @{ $build_profile{'master'} };
}

our $GITDIR = "$SRCDIR/myth-git";

our @pluginConf;
if ( $OPT{plugins} )
{
    @pluginConf = split /,/, $OPT{plugins};
    @pluginConf = grep(s/^/--enable-/, @pluginConf);
    unshift @pluginConf, '--disable-all';
}
else
{
    @pluginConf = (
        '--enable-opengl',
        '--enable-mythgallery',
        '--enable-exif',
        '--enable-new-exif',
    );
}


# configure mythplugins, and mythtv, etc
our %conf = (
  'mythplugins'
  =>  [
        '--prefix=' . $PREFIX,
        @pluginConf
      ],
  'mythtv'
  =>  [
        '--prefix=' . $PREFIX,
        '--runprefix=../Resources',
        '--enable-libmp3lame',
        # To "cross compile" something for a lesser Mac:
        #'--tune=G3',
        #'--disable-altivec',
      ],
);

# configure mythplugins, and mythtv, etc
our %makecleanopt = (
  'mythplugins'
  =>  [
        'distclean',
      ],
);

# Source code version.pro needs to call subversion binary
#
use File::Basename;
our $gitpath = dirname $git;

# Clean the environment
$ENV{'PATH'} = "$PREFIX/bin:/bin:/usr/bin:/usr/sbin:$gitpath";
$ENV{'PKG_CONFIG_PATH'} = "$PREFIX/lib/pkgconfig:";
delete $ENV{'CPP'};
delete $ENV{'CXXCPP'};
$ENV{'CFLAGS'} = $ENV{'CXXFLAGS'} = $ENV{'CPPFLAGS'} = "-I$PREFIX/include";
$ENV{'LDFLAGS'} = "-F/System/Library/Frameworks -L/usr/lib -L$PREFIX/lib";
$ENV{'PREFIX'} = $PREFIX;

# set up Qt environment
$ENV{'QTDIR'} = $PREFIX;

# If environment is setup to use distcc, take advantage of it
our $standard_make = '/usr/bin/make';
our $parallel_make = $standard_make;
our $parallel_make_flags = '';

if ( $ENV{'DISTCC_HOSTS'} )
{
    my @hosts = split m/\s+/, $ENV{'DISTCC_HOSTS'};
    my $numhosts = $#hosts + 1;
    Verbose("Using ", $numhosts * 2, " DistCC jobs on $numhosts build hosts:",
             join ', ', @hosts);
    $parallel_make_flags = '-j' . $numhosts * 2;
}

# Ditto for multi-cpu setups:
my $cmd = "/usr/bin/hostinfo | grep 'processors\$'";
Verbose($cmd);
my $cpus = `$cmd`; chomp $cpus;
$cpus =~ s/.*, (\d+) processors$/$1/;
if ( $cpus gt 1 )
{
    Verbose("Using", $cpus+1, "jobs on $cpus parallel CPUs");
    ++$cpus;
    $parallel_make_flags = "-j$cpus";
}

$parallel_make .= " $parallel_make_flags";

# Auto-disable mixed 64/32bit:
if ( `sysctl -n hw.cpu64bit_capable` eq "1\n" )
{
    Verbose('OS is 64bit. Enabling 64bit for this build...');
    $OPT{'m32'} = 0;
    $OPT{'m64'} = 1;
    Verbose('Enabling 64-bit mode');
    $ENV{'CFLAGS'}    .= ' -m64';
    $ENV{'CPPFLAGS'}  .= ' -m64';
    $ENV{'CXXFLAGS'}  .= ' -m64';
    $ENV{'ECXXFLAGS'} .= ' -m64';  # MythTV configure
    $ENV{'LDFLAGS'}   .= ' -m64';
}

# We set 32-bit mode via environment variables.
# The messier alternative would be to tweak all the configure arguments.
if ( $OPT{'m32'} )
{
    Verbose('Forcing 32-bit mode');
    $ENV{'CFLAGS'}    .= ' -m32';
    $ENV{'CPPFLAGS'}  .= ' -m32';
    $ENV{'CXXFLAGS'}  .= ' -m32';
    $ENV{'ECXXFLAGS'} .= ' -m32';  # MythTV configure
    $ENV{'LDFLAGS'}   .= ' -m32';
}

### Distclean?
if ( $OPT{'distclean'} )
{
    Syscall([ '/bin/rm', '-f',       '$PREFIX/bin/myth*'    ]);
    Syscall([ '/bin/rm', '-f', '-r', '$PREFIX/lib/libmyth*' ]);
    Syscall([ '/bin/rm', '-f', '-r', '$PREFIX/lib/mythtv'   ]);
    Syscall([ '/bin/rm', '-f', '-r', '$PREFIX/share/mythtv' ]);
    Syscall([ 'find', $GITDIR, '-name', '*.o',     '-delete' ]);
    Syscall([ 'find', $GITDIR, '-name', '*.a',     '-delete' ]);
    Syscall([ 'find', $GITDIR, '-name', '*.dylib', '-delete' ]);
    Syscall([ 'find', $GITDIR, '-name', '*.orig',  '-delete' ]);
    Syscall([ 'find', $GITDIR, '-name', '*.rej',   '-delete' ]);
    exit;
}

### Check for app present in target location
our $MFE = "$SCRIPTDIR/MythFrontend.app";
if ( -d $MFE )
{
    &Complain(<<END);
$MFE already exists

Error: a MythFrontend application exists where we were planning
to build one. Please move this application away before running
this script.

END
    exit;
}

### Third party packages
my ( @build_depends, %seen_depends );
my @comps = ( 'mythtv', @components, 'packaging' );

# Deal with user-supplied skip arguments
if ( $OPT{'mythtvskip'} )
{   @comps = grep(!m/mythtv/,      @comps)   }
if ( $OPT{'pluginskip'} )
{   @comps = grep(!m/mythplugins/, @comps)   }

if ( ! @comps )
{
    &Complain("Nothing to build! Too many ...skip arguments?");
    exit;
}

Verbose("Including components:", @comps);

# If no Git in path, and we are checking something out, build Git:
if ( ( ! $git || $git =~ m/no git in / ) && ! $OPT{'nohead'} )
{
    $git = "$PREFIX/bin/git";
    @build_depends = ( 'git' );
}

foreach my $comp (@comps)
{
    foreach my $dep (@{ $depend_order{$comp} })
    {
        unless (exists $seen_depends{$dep})
        {
            push(@build_depends, $dep);
            $seen_depends{$dep} = 1;
        }
    }
}
foreach my $sw ( @build_depends )
{
    # Get info about this package
    my $pkg = $depend{$sw};
    my $url = $pkg->{'url'};
    my $filename = $url;
    $filename =~ s|^.+/([^/]+)$|$1|;
    my $dirname = $filename;
    $filename = $ARCHIVEDIR . '/' . $filename;
    $dirname =~ s|\.tar\.gz$||;
    $dirname =~ s|\.tar\.bz2$||;

    chdir($SRCDIR);

    # Download and decompress
    unless ( -e $filename )
    {
        Verbose("Downloading $sw");
        if ($pkg->{'url-type'} eq 'git') {
          # fetch using git
          # git clone $url
          Verbose("Checking out $sw source code");
          Syscall([ $git, 'clone', $url ]) or die;

        } else {
          # do it the old way
          unless (Syscall([ '/usr/bin/curl', '-f', '-L', $url, '>', $filename ],
                           'munge' => 1))
            {
              Syscall([ '/bin/rm', $filename ]) if (-e $filename);
              die;
            }
        }
      } else {
        Verbose("Using previously downloaded $sw");
        if ($pkg->{'url-type'} eq 'git') {
          Verbose("doing a git pull of $sw");
          
          #Syscall([ $git, 'pull' ]) or die;   

       }       
        
      }

    if ( $pkg->{'skip'} )
    {   next   }

    if ( -d $dirname )
    {
        if ( $OPT{'thirdclean'} )
        {
            Verbose("Removing previous build of $sw");
            Syscall([ '/bin/rm', '-f', '-r', $dirname ]) or die;
        }

        if ( $OPT{'thirdskip'} )
        {
            Verbose("Using previous build of $sw");
            next;
        }

        Verbose("Using previously unpacked $sw");
    }
    else
    {
        Verbose("Unpacking $sw");
        if ( substr($filename,-3) eq ".gz" )
        {   Syscall([ '/usr/bin/tar', '-xzf', $filename ]) or die   }
        elsif ( substr($filename,-4) eq ".bz2" )
        {   Syscall([ '/usr/bin/tar', '-xjf', $filename ]) or die   }
        else
        {
            &Complain("Cannot unpack file $filename");
            exit;
        }
    }

    # Configure
    chdir($dirname);
    unless (-e '.osx-config')
    {
        Verbose("Configuring $sw");
        if ( $pkg->{'pre-conf'} )
        {   Syscall([ $pkg->{'pre-conf'} ], 'munge' => 1) or die   }

        my (@configure, $munge);

        if ( $pkg->{'conf-cmd'} )
        {
            push(@configure, $pkg->{'conf-cmd'});
            $munge = 1;
        }
        else
        {
            push(@configure, './configure',
                       '--prefix=$PREFIX',
                       '--disable-static',
                       '--enable-shared');
        }
        if ( $pkg->{'conf'} )
        {
            push(@configure, @{ $pkg->{'conf'} });
        }
        Syscall(\@configure, 'interpolate' => 1, 'munge' => $munge) or die;
        if ( $pkg->{'post-conf'} )
        {
            Syscall([ $pkg->{'post-conf'} ], 'munge' => 1) or die;
        }
        Syscall([ '/usr/bin/touch', '.osx-config' ]) or die;
    }
    else
    {   Verbose("Using previously configured $sw")   }

    # Build and install
    unless (-e '.osx-built')
    {
        Verbose("Making $sw");
        my (@make);

        push(@make, $standard_make);
        if ( $pkg->{'parallel-make'} && $parallel_make_flags )
        {   push(@make, $parallel_make_flags)   }

        if ( $pkg->{'make'} )
        {   push(@make, @{ $pkg->{'make'} })   }
        else
        {   push(@make, 'all', 'install')   }

        Syscall(\@make) or die;
        if ( $pkg->{'post-make'} )
        {
            Syscall([ $pkg->{'post-make'} ], 'munge' => 1) or die;
        }
        Syscall([ '/usr/bin/touch', '.osx-built' ]) or die;
    }
    else
    {
        Verbose("Using previously built $sw");
    }
}


### build MythTV

# Clean any previously installed libraries
if ( $cleanLibs )
{
    if ( $OPT{'mythtvskip'} )
    {
        &Complain("Cannot skip building mythtv src if also cleaning");
        exit;
    }
    Verbose("Cleaning previous installs of MythTV");
    my @mythlibs = glob "$PREFIX/lib/libmyth*";
    if ( scalar @mythlibs )
    {
        Syscall([ '/bin/rm', @mythlibs ]) or die;
    }
    foreach my $dir ('include', 'lib', 'share')
    {
        if ( -d "$PREFIX/$dir/mythtv" )
        {
            Syscall([ '/bin/rm', '-f', '-r', "$PREFIX/$dir/mythtv" ]) or die;
        }
    }
}

#
# Work out Git branches, revisions and tags.
# Note these vars are unused if nohead or srcdir set!
#
my $gitrepository = 'git://github.com/MythTV/mythtv.git';
my $gitpackaging  = 'git://github.com/MythTV/packaging.git';

my $gitfetch  = 0;  # Synchronise cloned database copy before checkout?
my $gitpull   = 1;  # Cause a fast-forward
my $gitrevSHA = 0;
my $gitrevert = 0;  # Undo any local changes?

if ( $OPT{'gitrev'} )
{
    # This arg. could be '64d9d7c5...' (up to 40 hex digits),
    # a branch like 'mythtv-rec', 'nigelfixes' or 'master',
    # or a tag name like 'fixes/0.24'.
 
    $gitrevision = $OPT{'gitrev'};

    # If it is a hex revision, we checkout and don't pull mythtv src
    if ( $gitrevision =~ /^[0-9a-f]{7,40}$/ )
    {
        $gitrevSHA = 1;
        $gitfetch  = 1;  # Rev. might be newer than local cache
        $gitpull   = 0;  # Checkout creates "detached HEAD", git pull will fail
    }
}

# Retrieve source
if ( $OPT{'srcdir'} )
{
    chdir($SCRIPTDIR);
    Syscall(['rm', '-fr', $GITDIR]);
    Syscall(['mkdir', '-p', $GITDIR]);
    foreach my $dir ( @comps )
    {
        Syscall(['cp', '-pR', "$OPT{'srcdir'}/$dir", "$GITDIR/$dir"]);
    }
    Syscall("mkdir -p $GITDIR/mythtv/config")
}
elsif ( ! $OPT{'nohead'} )
{
    # Only do 'git clone' if mythtv directory does not exist.
    # Always do 'git checkout' to make sure we have the right branch,
    # then 'git pull' to get up to date.
    if ( ! -e $GITDIR )
    {
        Verbose("Checking out source code");
        Syscall([ $git, 'clone', $gitrepository, $GITDIR ]) or die;
    }
    if ( ! -e "$GITDIR/packaging" )
    {
        Verbose("Checking out packaging code");
        Syscall([ $git, 'clone',
                   $gitpackaging, $GITDIR . '/packaging' ]) or die;
    }

    # Remove Nigel's frontend building speedup hack
    chdir "$GITDIR/mythtv" or die;
    &DoSpeedupHacks('programs/programs.pro', '');

    my @gitcheckoutflags;

    if ( $gitrevert )
    {   @gitcheckoutflags = ( 'checkout', '--force', $gitrevision )   }
    else
    {   @gitcheckoutflags = ( 'checkout', '--merge', $gitrevision )   }


    chdir $GITDIR;
    if ( $gitfetch )   # Update Git DB
    {   Syscall([ $git, 'fetch' ]) or die   }
    Syscall([ $git, @gitcheckoutflags ]) or die;
    if ( $gitpull )    # Fast-forward
    {   Syscall([ $git, 'pull' ]) or die   }

    chdir "$GITDIR/packaging";
    if ( $gitfetch )   # Update Git DB
    {   Syscall([ $git, 'fetch' ]) or die   }
    if ( $gitrevSHA )
    {
        Syscall([ $git, 'checkout', 'master' ]) or die;
        Syscall([ $git, 'merge',    'master' ]) or die;
    }
    else
    {
        Syscall([ $git, @gitcheckoutflags ]) or die;
        if ( $gitpull )   # Fast-forward
        {   Syscall([ $git, 'pull' ]) or die   }
    }
}


# Make a convenience (non-hidden) directory for editing src code:
system("ln -sf $GITDIR $SCRIPTDIR/src");

# Build MythTV and any plugins
foreach my $comp (@comps)
{
    my $compdir = "$GITDIR/$comp/" ;

    chdir $compdir || die "No source directory $compdir";

    if ( ! -e "$comp.pro" and ! -e 'Makefile' and ! -e 'configure' )
    {
        &Complain("Nothing to configure/make in $compdir");
        next;
    }

    if ( $OPT{'clean'} && -e 'Makefile' )
    {
        Verbose("Cleaning $comp");
        Syscall([ $standard_make, 'distclean' ]) or die;
    }
    #else
    #{
    #    # clean the Makefiles, as process requires PREFIX hacking
    #    &CleanMakefiles();
    #}

    # Apply any nasty mac-specific patches
    if ( $patches{$comp} )
    {
        Syscall([ "echo '$patches{$comp}' | patch -p0 --forward" ]);
    }

    # configure and make
    if ( $makecleanopt{$comp} && -e 'Makefile' && ! $OPT{'noclean'} )
    {
        my @makecleancom = $standard_make;
        push(@makecleancom, @{ $makecleanopt{$comp} }) if $makecleanopt{$comp};
        Syscall([ @makecleancom ]) or die;
    }
    if ( -e 'configure' && ! $OPT{'noclean'} )
    {
        Verbose("Configuring $comp");
        my @config = './configure';
        push(@config, @{ $conf{$comp} }) if $conf{$comp};
        if ( $comp eq 'mythtv' && $backend )
        {
            push @config, '--enable-backend'
        }
        if ( $OPT{'profile'} )
        {
            push @config, '--compile-type=profile'
        }
        if ( $OPT{'debug'} )
        {
            push @config, '--compile-type=debug'
        }
        if ( $comp eq 'mythtv' && ! $ENV{'DISTCC_HOSTS'} )
        {
            push @config, '--disable-distcc'
        }
        Syscall([ @config ]) or die;
    }
    if ($OPT{'config-only'}) { exit; }
    if ( -e "$comp.pro" )
    {
        Verbose("Running qmake for $comp");
        my @qmake_opts = (
            'QMAKE_LFLAGS+=-Wl,-search_paths_first',
            'INCLUDEPATH+="' . $PREFIX . '/include"',
            'LIBS+=-L/usr/lib -L"' . $PREFIX . '/lib"'
            );
        Syscall([ $PREFIX . '/bin/qmake',
                   'PREFIX=../Resources',
                   @qmake_opts,
                   "$comp.pro" ]) or die;
    }
    if ( $comp eq 'mythtv' )
    {
        # Remove/add Nigel's frontend building speedup hack
        &DoSpeedupHacks('programs/programs.pro',
                        'mythfrontend mythavtest mythpreviewgen mythwelcome');
    }

    Verbose("Making $comp");
    Syscall([ $parallel_make ]) or die;
#    # install
#    # This requires a change from the compiled-in relative
#    # PREFIX to our absolute path of the temp install location.
#    &CleanMakefiles();
#    Verbose("Running qmake for $comp install");
#    Syscall([ $PREFIX . '/bin/qmake',
#               'PREFIX=' . $PREFIX,
#               @qmake_opts,
#               "$comp.pro" ]) or die;
    Verbose("Installing $comp");
    Syscall([ $standard_make,
               'install' ]) or die;

    if ( $cleanLibs && $comp eq 'mythtv' )
    {
        # If we cleaned the libs, make install will have recopied them,
        # which means any dynamic libraries that the static libraries depend on
        # are newer than the table of contents. Hence we need to regenerate it:
        my @mythlibs = glob "$PREFIX/lib/libmyth*.a";
        if ( scalar @mythlibs )
        {
            Verbose("Running ranlib on reinstalled static libraries");
            foreach my $lib (@mythlibs)
            {   Syscall("ranlib $lib") or die }
        }
    }
}

### Build version string
our $VERS = `find $PREFIX/lib -name 'libmyth-[0-9].[0-9][0-9].[0-9].dylib'`;
chomp $VERS;
$VERS =~ s/^.*\-(.*)\.dylib$/$1/s;
$VERS .= '.' . $OPT{'version'} if $OPT{'version'};

### Program which creates bundles:
our @bundler = "$GITDIR/packaging/OSX/build/osx-bundler.pl";
if ( $OPT{'verbose'} )
{   push @bundler, '--verbose'   }


### Framework that has a screwed up link dependency path
my $AVCfw = '/Developer/FireWireSDK*/Examples/' .
            'Framework/AVCVideoServices.framework';
my @AVCfw = split / /, `ls -d $AVCfw`;
$AVCfw = pop @AVCfw;
chop $AVCfw;

### Create each package.
### Note that this is a bit of a waste of disk space,
### because there are now multiple copies of each library.

if ( $jobtools )
{   push @targets, @targetsJT   }

if ( $backend )
{   push @targets, @targetsBE   }

foreach my $target ( @targets )
{
    my $finalTarget = "$SCRIPTDIR/$target.app";
    my $builtTarget = lc $target;

    # Get a fresh copy of the binary
    Verbose("Building self-contained $target");
    Syscall([ 'rm', '-fr', $finalTarget ]) or die;
    Syscall([ 'cp',  "$GITDIR/mythtv/programs/$builtTarget/$builtTarget",
                      "$SCRIPTDIR/$target" ]) or die;

    # Convert it to a bundled .app
    Syscall([ @bundler, "$SCRIPTDIR/$target",
               "$PREFIX/lib/", "$PREFIX/lib/mysql" ]) or die;

    # Remove copy of binary
    unlink "$SCRIPTDIR/$target" or die;

    if ( $AVCfw )
    {   &RecursiveCopy($AVCfw, "$finalTarget/Contents/Frameworks")   }

    # Themes are required by all GUI apps. The filters and plugins are not
    # used by mythtv-setup or mythwelcome, but for simplicity, do them all.
    if ( $target eq "MythAVTest" or $target eq "MythFrontend" or
         $target eq "MythWelcome" or $target =~ m/^MythTV-/ )
    {
        my $res  = "$finalTarget/Contents/Resources";
        my $libs = "$res/lib";
        my $plug = "$libs/mythtv/plugins";

        # Install themes, filters, etc.
        Verbose("Installing resources into $target");
        mkdir $res; mkdir $libs;
        &RecursiveCopy("$PREFIX/lib/mythtv", $libs);
        mkdir "$res/share";
        &RecursiveCopy("$PREFIX/share/mythtv", "$res/share");

        # Correct the library paths for the filters and plugins
        foreach my $lib ( glob "$libs/mythtv/*/*" )
        {   Syscall([ @bundler, $lib, "$PREFIX/lib/" ]) or die   }

        if ( -e $plug )
        {
            # Allow Finder's 'Get Info' to manage plugin list:
            Syscall([ 'mv', $plug, "$finalTarget/Contents/Plugins" ]) or die;
            Syscall([ 'ln', '-s', "../../../Plugins", $plug ]) or die;
        }

        # The icon
        Syscall([ 'cp',
                   "$GITDIR/mythtv/programs/mythfrontend/mythfrontend.icns",
                   "$res/application.icns" ]) or die;
        Syscall([ '/Developer/Tools/SetFile', '-a', 'C', $finalTarget ])
            or die;
    }

    if ( $target eq "MythFrontend" )
    {
        foreach my $extra ( 'ignyte', 'mythpreviewgen', 'mtd' )
        {
            if ( -e "$PREFIX/bin/$extra" )
            {
                Verbose("Installing $extra into $target");
                Syscall([ 'cp', "$PREFIX/bin/$extra",
                           "$finalTarget/Contents/MacOS" ]) or die;

                Verbose('Updating lib paths of',
                         "$finalTarget/Contents/MacOS/$extra");
                Syscall([ @bundler, "$finalTarget/Contents/MacOS/$extra" ])
                    or die;
                &AddFakeBinDir($finalTarget);
            }
        }

        # Allow playback of region encoded DVDs
        mkdir("$finalTarget/Contents/Plugins");
        Syscall([ 'cp', "$PREFIX/lib/libdvdcss.2.dylib",
                         "$finalTarget/Contents/Plugins" ]) or die;

        # Allow opening of GIFs and JPEGs:
        mkdir("$finalTarget/Contents/MacOS/imageformats");
        foreach my $plugin ( 'libqgif.dylib', 'libqjpeg.dylib' )
        {
            my $pluginSrc = "$PREFIX/plugins/imageformats/$plugin";
            if ( -e $pluginSrc )
            {
                Syscall([ 'cp', $pluginSrc,
                           "$finalTarget/Contents/MacOS/imageformats" ])
                    or die;
                Syscall([ @bundler,
                           "$finalTarget/Contents/MacOS/imageformats/$plugin" ])
                    or die;
            }
        }
    }

    if ( $target eq "MythWelcome" )
    {
        Verbose("Installing mythfrontend into $target");
        Syscall([ 'cp', "$PREFIX/bin/mythfrontend",
                         "$finalTarget/Contents/MacOS" ]) or die;
        Syscall([ @bundler, "$finalTarget/Contents/MacOS/mythfrontend" ])
            or die;
        &AddFakeBinDir($finalTarget);

        # For some unknown reason, mythfrontend looks here for support files:
        Syscall([ 'ln', '-s', "../Resources/share",   # themes
                               "../Resources/lib",     # filters/plugins
                   "$finalTarget/Contents/MacOS" ]) or die;
    }

    # Run 'rebase' on all the frameworks, for slightly faster loading.
    # Note that we process the real library, not symlinks to it,
    # to prevent rebase erroneously creating copies:
    my @libs = glob "$finalTarget/Contents/Frameworks/*";
    @libs = grep(s,(.*/)(\w+).framework$,$1$2.framework/Versions/A/$2, , @libs);

    # Also process all the filters/plugins:
    push(@libs, glob "$finalTarget/Contents/Resources/lib/mythtv/*/*");

    if ( $OPT{'verbose'} )
    {   Syscall([ 'rebase', '-v', @libs ]) or die   }
    else
    {   Syscall([ 'rebase', @libs ]) or die   }
}

if ( $backend && grep(m/MythBackend/, @targets) )
{
    my $BE = "$SCRIPTDIR/MythBackend.app";

    # Copy XML files that UPnP requires:
    my $share = "$BE/Contents/Resources/share/mythtv";
    Syscall([ 'mkdir', '-p', $share ]) or die;
    Syscall([ 'cp', glob("$PREFIX/share/mythtv/*.xml"), $share ]) or die;

    # Same for default web server page:
    Syscall([ 'cp', '-pR', "$PREFIX/share/mythtv/html", $share ]) or die;

    # The backend gets all the useful binaries it might call:
    foreach my $binary ( 'mythjobqueue', 'mythcommflag',
                         'mythpreviewgen', 'mythtranscode', 'mythfilldatabase' )
    {
        my $SRC  = "$PREFIX/bin/$binary";
        if ( -e $SRC )
        {
            Verbose("Installing $SRC into $BE");
            Syscall([ '/bin/cp', $SRC, "$BE/Contents/MacOS" ]) or die;

            Verbose("Updating lib paths of $BE/Contents/MacOS/$binary");
            Syscall([ @bundler, "$BE/Contents/MacOS/$binary" ]) or die;
        }
    }
    &AddFakeBinDir($BE);
}

if ( $backend && grep(m/MythTV-Setup/, @targets) )
{
    my $SET = "$SCRIPTDIR/MythTV-Setup.app";
    my $SRC  = "$PREFIX/bin/mythfilldatabase";
    if ( -e $SRC )
    {
        Verbose("Installing $SRC into $SET");
        Syscall([ '/bin/cp', $SRC, "$SET/Contents/MacOS" ]) or die;

        Verbose("Updating lib paths of $SET/Contents/MacOS/mythfilldatabase");
        Syscall([ @bundler, "$SET/Contents/MacOS/mythfilldatabase" ]) or die;
    }
    &AddFakeBinDir($SET);
}

if ( $jobtools )
{
    # JobQueue also gets some binaries it might call:
    my $JQ   = "$SCRIPTDIR/MythJobQueue.app";
    my $DEST = "$JQ/Contents/MacOS";
    my $SRC  = "$PREFIX/bin/mythcommflag";

    Syscall([ '/bin/cp', $SRC, $DEST ]) or die;
    &AddFakeBinDir($JQ);
    Verbose("Updating lib paths of $DEST/mythcommflag");
    Syscall([ @bundler, "$DEST/mythcommflag" ]) or die;

    $SRC  = "$PREFIX/bin/mythtranscode.app/Contents/MacOS/mythtranscode";
    if ( -e $SRC )
    {
        Verbose("Installing $SRC into $JQ");
        Syscall([ '/bin/cp', $SRC, $DEST ]) or die;
        Verbose("Updating lib paths of $DEST/mythtranscode");
        Syscall([ @bundler, "$DEST/mythtranscode" ]) or die;
    }
}

# Clean tmp files. Most of these are leftovers from configure:
#
Verbose('Cleaning build tmp directory');
Syscall([ 'rm', '-fr', $WORKDIR . '/tmp' ]) or die;
Syscall([ 'mkdir',     $WORKDIR . '/tmp' ]) or die;

if ($OPT{usehdimage} && !$OPT{leavehdimage} )
{
    Verbose("Dismounting case-sensitive build device");
    UnmountHDImage();
}

Verbose("Build complete. Self-contained package is at:\n\n    $MFE\n");

### end script
exit 0;


######################################
## RecursiveCopy copies a directory tree, stripping out .git
## directories and properly managing static libraries.
######################################

sub RecursiveCopy($$)
{
    my ($src, $dst) = @_;

    # First copy absolutely everything
    Syscall([ '/bin/cp', '-pR', "$src", "$dst"]) or die;

    # Then strip out any .git directories
    my @files = map { chomp $_; $_ } `find $dst -name .git`;
    if ( scalar @files )
    {
        Syscall([ '/bin/rm', '-f', '-r', @files ]);
    }

    # And make sure any static libraries are properly relocated.
    my @libs = map { chomp $_; $_ } `find $dst -name "lib*.a"`;
    if ( scalar @libs )
    {
        Syscall([ 'ranlib', '-s', @libs ]);
    }
}

######################################
## CleanMakefiles removes every generated Makefile
## from our MythTV build that contains PREFIX.
## Necessary when we change the
## PREFIX variable.
######################################

sub CleanMakefiles
{
    Verbose("Cleaning MythTV makefiles containing PREFIX");
    Syscall([ 'find', '.', '-name', 'Makefile', '-exec',
               'egrep', '-q', 'qmake.*PREFIX', '{}', ';', '-delete' ]) or die;
} # end CleanMakefiles


######################################
## Syscall wrappers the Perl "system"
## routine with verbosity and error
## checking.
######################################

sub Syscall($%)
{
    my ($arglist, %opts) = @_;

    unless (ref $arglist)
    {
        $arglist = [ $arglist ];
    }
    if ( $opts{'interpolate'} )
    {
        my @args;
        foreach my $arg (@$arglist)
        {
            $arg =~ s/\$PREFIX/$PREFIX/ge;
            $arg =~ s/\$parallel_make_flags/$parallel_make_flags/ge;
            push(@args, $arg);
        }
        $arglist = \@args;
    }
    if ( $opts{'munge'} )
    {
        $arglist = [ join(' ', @$arglist) ];
    }
    # clean out any null arguments
    $arglist = [ map $_, @$arglist ];
    Verbose('Current working directory: ' . `pwd` );
    Verbose(@$arglist);
    my $ret = system(@$arglist);
    if ( $ret )
    {
        &Complain('Failed system call: "', @$arglist,
                  '" with error code', $ret >> 8);
    }
    return ($ret == 0);
} # end Syscall


######################################
## Verbose prints messages in verbose
## mode.
######################################

sub Verbose
{
    print STDERR '[osx-pkg] ' . join(' ', @_) . "\n"
        if $OPT{'verbose'};
} # end Verbose


######################################
## Complain prints messages in any
## verbosity mode.
######################################

sub Complain
{
    print STDERR '[osx-pkg] ' . join(' ', @_) . "\n";
} # end Complain


######################################
## Manage usehdimage disk image
######################################

sub MountHDImage
{
    if ( ! HDImageDevice() )
    {
        if ( -e "$SCRIPTDIR/.osx-packager.dmg" )
        {
            Verbose("Mounting existing UFS disk image for the build");
        }
        else
        {
            Verbose("Creating a case-sensitive (UFS) disk image for the build");
            Syscall(['hdiutil', 'create', '-size', '2048m',
                     "$SCRIPTDIR/.osx-packager.dmg", '-volname',
                     'MythTvPackagerHDImage', '-fs', 'UFS', '-quiet']) || die;
        }

        Syscall(['hdiutil', 'mount',
                  "$SCRIPTDIR/.osx-packager.dmg",
                  '-mountpoint', $WORKDIR, '-quiet']) || die;
    }

    # configure defaults to /tmp and OSX barfs when mv crosses
    # filesystems so tell configure to put temp files on the image

    $ENV{TMPDIR} = $WORKDIR . "/tmp";
    mkdir $ENV{TMPDIR};
}

sub UnmountHDImage
{
    my $device = HDImageDevice();
    if ( $device )
    {
        Syscall(['hdiutil', 'detach', $device, '-force']);
    }
}

sub HDImageDevice
{
    my @dev = split ' ', `/sbin/mount | grep $WORKDIR`;
    $dev[0];
}

sub CaseSensitiveFilesystem
{
    my $funky = $SCRIPTDIR . "/.osx-packager.FunkyStuff";
    my $unfunky = substr($funky, 0, -10) . "FUNKySTuFF";

    unlink $funky if -e $funky;
    `touch $funky`;
    my $sensitivity = ! -e $unfunky;
    unlink $funky;

    return $sensitivity;
}


######################################
## Remove or add Nigel's speedup hacks
######################################

sub DoSpeedupHacks($$)
{
    my ($file, $subdirs) = @_;

    Verbose("Removing Nigel's hacks from file $file");

    open(IN,  $file)         or die;
    open(OUT, ">$file.orig") or die;
    while ( <IN> )
    {
        if ( m/^# Nigel/ )  # Skip
        {  last  }
        print OUT;
    }
    if ( ! $backend && ! $jobtools && $subdirs )
    {
        # Nigel's hack to speedup building
        print OUT "# Nigel\'s speedup hack:\n";
        print OUT "SUBDIRS = $subdirs\n";
    }
    close IN; close OUT;
    rename("$file.orig", $file);
}

#######################################################
## Parts of MythTV try to call helper apps like this:
## gContext->GetInstallPrefix() + "/bin/mythtranscode";
## which means we need a bin directory.
#######################################################

sub AddFakeBinDir($)
{
    my ($target) = @_;

    Syscall("mkdir -p $target/Contents/Resources");
    Syscall(['ln', '-sf', '../MacOS', "$target/Contents/Resources/bin"]);
}

### end file
1;
