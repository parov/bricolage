#!/usr/bin/perl -w

use strict;
use File::Spec::Functions qw(catdir updir);
use FindBin;
use lib catdir $FindBin::Bin, updir, 'lib';
use bric_upgrade;
use File::Find;
use Bric::Config qw(BURN_COMP_ROOT);
use Bric::Util::Trans::FS;

my $fs = Bric::Util::Trans::FS->new;

find(\&rm_dhandler, BURN_COMP_ROOT);

sub rm_dhandler {
    return unless $_ eq 'dhandler';
    print "Deleting $File::Find::name\n";
    $fs->del($File::Find::name);
}

__END__

This script will delete all the dhandlers in the Template root. This is
necessary because these files are no longer needed by Bricolage, which
auto-generated them prior to 1.7.2.
