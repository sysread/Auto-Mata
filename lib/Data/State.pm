package Data::State;
# ABSTRACT: State machine grease

use strict;
use warnings;
use parent 'Exporter';
use Carp;
use Data::Dumper;
use Iterator::Simple qw(iterator);
use Type::Utils -all;
use Types::Standard -all;

our @EXPORT = qw(
  machine
  transition
  ready
  terminal
  to
  on
  with
);

#sub machine (&) {
#  my $code = shift;
#  my %fsm = (ready => undef, terminal => undef, states => {});
#  do { local $_ = \%fsm; $code->() };
#
#  croak 'no ready state defined' unless $fsm{ready};
#  croak 'no terminal state defined' unless $fsm{terminal};
#  croak 'no transitions defined for ready state' unless $fsm{states}{$fsm{ready}};
#
#  sub {
#    my $acc = shift;
#    my $state = $fsm{ready};
#
#    iterator {
#      return if $state eq $fsm{terminal};
#
#      foreach my $to (keys %{$fsm{states}{$state}}) {
#        foreach my $transition (@{$fsm{states}{$state}{$to}}) {
#          my ($on, $inlined, $with) = @$transition;
#          if ($inlined ? eval $inlined : $on->check($acc)) {
#            do { local $_ = $acc; $with->() } if $with;
#            $state = $to;
#            return $state;
#          }
#        }
#      }
#
#      croak "no transitions match $state";
#    };
#  };
#}

#sub transition ($%) {
#  my ($from, %param) = @_;
#  my $to   = $param{to};
#  my $on   = $param{on}   // Any;
#  my $with = $param{with} // sub { 1 };
#
#  $_->{states}{$from} //= {};
#  $_->{states}{$from}{$to} //= [];
#
#  my $inlined = $on->inline_check('$acc')
#    if $on->can_be_inlined;
#
#  push @{$_->{states}{$from}{$to}}, [$on, $inlined, $with];
#}

our $Ident = declare 'Ident', as StrMatch[qr/^[A-Z][_0-9A-Z]*$/i];
our $State = declare 'State', as Tuple[$Ident, Any];

sub machine (&) {
  my $code = shift;

  my (@states, %table);

  my %fsm = (
    ready       => undef,
    terminal    => undef,
    states      => \@states,
    transitions => \%table,
  );

  do { local $_ = \%fsm; $code->() };

  croak 'no ready state defined' unless $fsm{ready};
  croak 'no terminal state defined' unless $fsm{terminal};

  my $terminal = Tuple[Enum[$fsm{terminal}], Any];
  my $classify = classifier(@states);

  sub {
    my $state = [$fsm{ready}, shift];
    my $term;

    iterator {
      return if $term;

      if (my $match = $classify->($state)) {
        my ($next, $transform) = @{$table{$match->name}};
warn "$state->[0] -> $next: ", explain($state), "\n";
        do { local $_ = $state->[1]; $transform->() };
        $state = [$next, $state->[1]];

        $term = 1 if $terminal->check($state);
        return $next;
      }

      croak 'no transitions match ' . explain($state);
    };
  };
}

sub explain {
  my $state = shift;
  local $Data::Dumper::Indent = 0;
  local $Data::Dumper::Terse  = 1;
  Dumper($state);
}

sub transition ($%) {
  my ($from, %param) = @_;
  my $to   = $param{to};
  my $on   = $param{on} // Any;
  my $with = $param{with} // sub { $_ };
  my $init = declare sprintf('%s_TO_%s', $from, $to), as Tuple[Enum[$from], $on];
  push @{$_->{states}}, $init;
  $_->{transitions}{$init->name} = [$to, $with];
}

sub ready    ($)   { $_->{ready} = shift }
sub terminal ($)   { $_->{terminal} = shift };
sub to       ($;%) { (to   => shift, @_) }
sub on       ($;%) { (on   => shift, @_) }
sub with     (&;%) { (with => shift, @_) }

1;
