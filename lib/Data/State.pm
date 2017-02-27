package Data::State;
# ABSTRACT: State machine grease

use v5.10;
use strict;
use warnings;
use parent 'Exporter';
use Carp;
use Data::Dumper;
use List::Util qw(first);
use Type::Utils -all;
use Types::Standard -all;
use Type::Params qw(compile);

our @EXPORT = qw(
  machine
  ready
  terminal
  transition
  to
  on
  with
);

my $Ident = declare 'Ident', as StrMatch[qr/^[A-Z][_0-9A-Z]*$/i];
my $State = declare 'State', as Tuple[$Ident, Any];
my $Type  = declare 'Type',  as InstanceOf['Type::Tiny'];
my $Code  = declare 'Code',  as CodeRef;
coerce $Code, from Undef, via { sub {} };

sub machine (&) {
  my $code = shift;

  my @states;
  my %table;

  my %fsm = (
    ready  => undef,
    term   => undef,
    states => \@states,
    table  => \%table,
  );

  do { local $_ = \%fsm; $code->() };

  croak 'no ready state defined'
    unless $fsm{ready};

  croak 'no terminal state defined'
    unless $fsm{terminal};

  croak 'no transitions defined'
    unless @states;

  croak 'no transition defined for ready state'
    unless $table{$fsm{ready}};

  croak 'no transition defined to terminal state'
    unless first { $_->[0] eq $fsm{terminal} } values %table;

  my $ready    = Tuple[Enum[$fsm{ready}], Undef];
  my $terminal = Tuple[Enum[$fsm{term}],  Any];

  my @param;
  foreach my $state (@states) {
    my ($next, $mutate) = @{$table{$state->name}};
    push @param, $state, sub {
      debug("%s -> %s: %s", $_->[0], $next, explain($_->[1]));
      do { local $_ = $_->[1]; $mutate->() };
      $state = [$next, $_->[1]];
    };
  }

  my $fail = sub { croak 'no transitions match ' . explain($_) };
  my $transform = compile_match_on_type(@param, => $fail);

  return sub {
    my $state = [$fsm{ready}, shift];
    my $term;

    sub {
      return if $term;
      $state = $transform->($state);
      $term  = $terminal->check($state);
      return $state->[0];
    };
  };
}

sub ready ($) { $_->{ready} = shift }

sub terminal ($) { $_->{term} = shift }

sub to   ($;%) { (to   => shift, @_) }
sub on   ($;%) { (on   => shift, @_) }
sub with (&;%) { (with => shift, @_) }
sub transition ($%) {
  state $check = compile($Ident, $Ident, $Type, $Code);
  my ($arg, %param) = @_;
  my ($from, $to, $on, $with) = $check->($arg, @param{qw(to on with)});
  $with //= sub {};
  my $init = declare sprintf('%s_TO_%s', $from, $to), as Tuple[Enum[$from], $on];
  push @{$_->{states}}, $init;
  $_->{table}{$init->name} = [$to, $with];
}

sub debug {
  return unless $ENV{DEBUG_STATE};
  my ($msg, @args) = @_;
  printf("DEBUG> $msg\n", @args);
}

sub explain {
  my $state = shift;
  local $Data::Dumper::Indent = 0;
  local $Data::Dumper::Terse  = 1;
  Dumper($state);
}

1;
