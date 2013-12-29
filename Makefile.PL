use inc::Module::Install;

name     'Graphics-Framebuffer';
all_from 'lib/Graphics/Framebuffer.pm';
author   q{Richard Kelsch <rich@csst.net>};
license  'perl';

build_requires 'Test::More';

auto_install;

WriteAll;

