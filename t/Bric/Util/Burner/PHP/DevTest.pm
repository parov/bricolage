package Bric::Util::Burner::PHP::DevTest;

use strict;
use warnings;
use base qw(Bric::Util::Burner::DevTest);
use Test::More;

#sub test_burn : Test(80) {
sub test_burn : Test(no_plan) {
    my $self = shift;
    return "PHP::Interpreter not installed"
      unless eval { require PHP::Interpreter };
    require Bric::Util::Burner::PHP;
    return $self->subclass_burn_test(
        'PHP',
        'php',
        Bric::Biz::AssetType::BURNER_PHP,
    );
}

sub story_output {
    return q{<html><head>
<title></title>
</head><body>
<h1>This is a Test</h1>
<h2>2005.03.22</h1>
<p>This is a paragraph</p>
<p>Second paragraph</p>
<p>Third paragraph</p>
<blockquote>
<p>Ask not what your country can do for you. Ask what you can do for your country.</p>
<p>--John F. Kennedy, 1961.01.20</p>
</blockquote>
<h4>My URI: /testing/sub/2005/03/22/test_burn</h4>
<div>Licensed under the BSD license</div>
</body></html>
}
}

sub story_page1 {
    return q{<html><head>
<title></title>
</head><body>
<h1>This is a Test</h1>
<h2>2005.03.22</h1>
<p>This is a paragraph</p>
<p>Second paragraph</p>
<p>Third paragraph</p>
<blockquote>
<p>Ask not what your country can do for you. Ask what you can do for your country.</p>
<p>--John F. Kennedy, 1961.01.20</p>
</blockquote>
<div class="page">
<p>Wee, page one paragraph</p>
<p>Another page one paragraph</p>
</div>
<h4>My URI: /testing/sub/2005/03/22/test_burn</h4>
<div>Licensed under the BSD license</div>
</body></html>
}
}

sub story_page2 {
    return q{<html><head>
<title></title>
</head><body>
<h1>This is a Test</h1>
<h2>2005.03.22</h1>
<p>Wee, page one paragraph</p>
<p>Another page one paragraph</p>
<div class="page">
<p>Wee, page two paragraph</p>
<p>Another page two paragraph</p>
</div>
<h4>My URI: /testing/sub/2005/03/22/test_burn</h4>
<div>Licensed under the BSD license</div>
</body></html>
}
}

1;
