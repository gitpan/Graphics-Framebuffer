#!perl -T

use strict;
use Test::More tests => 1;

BEGIN {
    use_ok('Graphics::Framebuffer') || print "Bail out!\n";
}

