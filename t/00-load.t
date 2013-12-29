#!perl -T

use Test::More tests => 1;

BEGIN {
    use_ok( 'Graphics::Framebuffer' ) || print "Bail out!\n";
}

diag( "Testing Graphics::Framebuffer $Graphics::Framebuffer::VERSION, Perl $], $^X" );
