#!perl -T

use strict;
use Test::More tests => 1;

use Graphics::Framebuffer;

my $fb = Graphics::Framebuffer->new();
isa_ok($fb, 'Graphics::Framebuffer');

