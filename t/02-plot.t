#!perl -T

use strict;
use Test::More tests => 481;

use Graphics::Framebuffer;

my $fb = Graphics::Framebuffer->new();
isa_ok($fb, 'Graphics::Framebuffer');

foreach my $y (0..479) {
    my $oldscreen = "$fb->{'SCREEN'}"; # Make a copy of the screen
    $fb->plot({'x'=>$y,'y'=>$y,'pixel_size'=>1});
    ok($oldscreen ne $fb->{'SCREEN'},'Point was plotted');
}
