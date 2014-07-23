#!perl -T

use strict;
use Test::More tests => 2;

use Graphics::Framebuffer;

my $fb = Graphics::Framebuffer->new();
isa_ok($fb, 'Graphics::Framebuffer');

my $oldscreen = $fb->{'SCREEN'};
$fb->polygon({'coordinates'=>[320,10,220,100,440,200,320,10],'pixel_size'=>1});
ok($oldscreen ne $fb->{'SCREEN'},'Polygon was drawn');
