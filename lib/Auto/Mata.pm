package Auto::Mata;
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

  #-----------------------------------------------------------------------------
  # Define transitions
  #-----------------------------------------------------------------------------
  my @states;
  my %table;
  my %map;

  my %fsm = (
    ready  => undef,
    term   => undef,
    states => \@states,
    table  => \%table,
    map    => \%map,
  );

  do { local $_ = \%fsm; $code->() };

  #-----------------------------------------------------------------------------
  # Validate sanity as much as possible without strict types and without
  # guarantees on the return type of transitions.
  #-----------------------------------------------------------------------------
  validate($fsm{ready}, $fsm{term}, \%map);

  #-----------------------------------------------------------------------------
  # Build function that transitions based on current state
  #-----------------------------------------------------------------------------
  my @param;
  foreach my $state (@states) {
    my ($to, $mutate) = @{$table{$state->name}};
    push @param, $state, sub {
      debug("%s -> %s: %s", $_->[0], $to, explain($_->[1]));

      my ($from, $data) = @$_;
      do { local $_ = $data; $mutate->() };
      @$_ = ($to, $data);
    };
  }

  my $fail = sub { croak 'no transitions match ' . explain($_) };
  my $transform = compile_match_on_type(@param, => $fail);
  my $terminal = Tuple[Enum[$fsm{term}], Any];

  #-----------------------------------------------------------------------------
  # Return function that builds a transition engine for the given input
  #-----------------------------------------------------------------------------
  return sub {
    my $state = [$fsm{ready}, shift];
    my $term;

    sub {
      return if $term;
      $transform->($state);
      $term = $terminal->check($state);
      wantarray ? @$state : $state->[1];
    };
  };
}

sub ready    ($)   { $_->{ready} = shift }
sub terminal ($)   { $_->{term} = shift }
sub to       ($;%) { (to   => shift, @_) }
sub on       ($;%) { (on   => shift, @_) }
sub with     (&;%) { (with => shift, @_) }

sub transition ($%) {
  state $check = compile($Ident, $Ident, $Type, $Code);
  my ($arg, %param) = @_;
  my ($from, $to, $on, $with) = $check->($arg, @param{qw(to on with)});
  my $init = declare sprintf('%s_TO_%s', $from, $to), as Tuple[Enum[$from], $on];
  push @{$_->{states}}, $init;
  $_->{table}{$init->name} = [$to, $with];
  $_->{map}{$from} //= {};
  $_->{map}{$from}{$to} = 1;
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

sub validate {
  my ($ready, $term, $map) = @_;

  croak 'no ready state defined'
    unless $ready;

  croak 'no terminal state defined'
    unless $term;

  croak 'no transitions defined'
    unless keys %$map;

  croak 'no transition defined for ready state'
    unless $map->{$ready};

  my $is_terminated;

  foreach my $from (keys %$map) {
    croak 'invalid transition from terminal state detected'
      if $from eq $term;

    foreach my $to (keys %{$map->{$from}}) {
      if ($to eq $term) {
        $is_terminated = 1;
        next;
      }

      croak "no subsequent states are reachable from $to"
        unless exists $map->{$to};
    }
  }

  croak 'no transition defined to terminal state'
    unless $is_terminated;
}

1;
