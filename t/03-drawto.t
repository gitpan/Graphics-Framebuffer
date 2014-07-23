#!perl -T

use strict;
use Test::More tests => 2;

use Graphics::Framebuffer;

my $fb = Graphics::Framebuffer->new();
isa_ok($fb, 'Graphics::Framebuffer');

my $oldscreen = $fb->{'SCREEN'};
$fb->plot({'x'=>0,'y'=>0,'pixel_size'=>1});
$fb->drawto({'x'=>639,'y'=>479,'pixel_size'=>1});
ok($oldscreen ne $fb->{'SCREEN'},'Line was drawn');
