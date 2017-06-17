package App::mimi::migration;

use strict;
use warnings;

use App::mimi::migration::sql;
use App::mimi::migration::perl;

sub build {
    my $class = shift;
    my ($type, @params) = @_;

    if ($type eq 'sql') {
        return App::mimi::migration::sql->new(@params);
    }
    elsif ($type eq 'pm') {
        return App::mimi::migration::perl->new(@params);
    }

    die "unknown type '$type'";
}

1;
