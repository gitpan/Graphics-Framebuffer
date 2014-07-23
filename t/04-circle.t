#!perl -T

# Circle calls ellipse, thus both are tested at once.

use strict;
use Test::More tests => 3;

use Graphics::Framebuffer;

my $fb = Graphics::Framebuffer->new();
isa_ok($fb, 'Graphics::Framebuffer');

my $oldscreen = $fb->{'SCREEN'};
$fb->circle({'x'=>320,'y'=>240,'radius'=>200,'pixel_size'=>1});
ok($oldscreen ne $fb->{'SCREEN'},'Circle was drawn');
$oldscreen = $fb->{'SCREEN'};
$fb->circle({'x'=>100,'y'=>100,'radius'=>80,'filled'=>1});
ok($oldscreen ne $fb->{'SCREEN'},'Filled circle was drawn');
