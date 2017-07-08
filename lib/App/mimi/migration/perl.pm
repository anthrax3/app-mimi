package App::mimi::migration::perl;

use strict;
use warnings;

use Carp qw(croak);

sub new {
    my $class = shift;

    my $self = {};
    bless $self, $class;

    return $self;
}

sub parse {
    my $self = shift;
    my ($file) = @_;

    my $code = $self->_slurp($file);

    my ($package) = $code =~ m/^package\s*(.*?);/ms;

    die "No package name found\n" unless $package;

    $self->{file}    = $file;
    $self->{package} = $package;

    return $self;
}

sub execute {
    my $self = shift;
    my ($dbh) = @_;

    my $e;
    eval {
        my $file = $self->{file};
        require $file;

        $self->{package}->migrate($dbh);

        1;
    } or do {
        $e = $@;
    };

    return { success => defined($e) ? 0 : 1, error => $e };
}

sub _slurp {
    my $self = shift;
    my ($file) = @_;

    open my $fh, '<', $file or croak "Can't open file '$file': $!";
    <$fh>;
}

1;
