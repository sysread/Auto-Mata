package Auto::Mata;
# ABSTRACT: State machine grease

=head1 SYNOPSIS

  use strict;
  use warnings;
  use Auto::Mata;
  use Types::Standard -types;

  my $NoData   = Undef,
  my $HasFirst = Tuple[Str];
  my $HasLast  = Tuple[Str, Str];
  my $Complete = Tuple[Str, Str, Int];

  sub get_input {
    my $query = shift;
    print "\n$query ";
    my $input = <STDIN>;
    chomp $input;
    return $input;
  }

  my $fsm = machine {
    ready 'READY';
    terminal 'TERM';

    transition 'READY', to 'FIRST',
      on $NoData,
      with { return [get_input("What is your first name? ")] };

    transition 'FIRST', to 'LAST',
      on $HasFirst,
      with { return [@$_, get_input("What is your last name? ")] };

    transition 'LAST', to 'AGE',
      on $HasLast,
      with { return [@$_, get_input("What is your age? ")] };

    transition 'AGE', to 'TERM',
      on $Complete;
  };

  my $prog = $fsm->(my $data);

  while ($prog->() ne 'TERM') {
    ;
  }

  printf "Hello %s %s, aged %d years!\n", @$data;

=head1 DESCRIPTION

Finite state machines (or automata) are a way of modeling the workflow of a
program as a series of dependent, programmable steps. They are very useful when
designing software that is guaranteed to behave in a predictable way.

In fact, most (all?) programs boil down to a FSM, with each conditional branch
defining a new state, although the author of the program may be unaware of this
and the state may be inspected in an ad hoc manner throughout.

Designing a program as a state machine from the outset is a useful technique to
consistently create reliable, well-behaved software. It forces the author to
think through each step in the program workflow, examining and modeling the data
at each stage during execution of the software.

=cut

use v5.10;
use strict;
use warnings;
use parent 'Exporter';
use Carp;
use Data::Dumper;
use List::Util qw(first reduce);
use Storable qw(dclone);
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

our $DEBUG = $ENV{DEBUG_AUTOMATA};

my $Ident = declare 'Ident', as StrMatch[qr/^[A-Z][_0-9A-Z]*$/i];
my $State = declare 'State', as Tuple[$Ident, Any];
my $Type  = declare 'Type',  as InstanceOf['Type::Tiny'];
my $Code  = declare 'Code',  as CodeRef;
coerce $Code, from Undef, via { sub { $_ } };

my $Transition = declare 'Transition', as Tuple[$Type, $Type, $Code];
my $Automata = declare 'Automata', as Dict[
  ready => Maybe[$Ident],
  term  => Maybe[$Ident],
  map   => Map[$Ident, Map[$Ident, $Transition]],
];

=head1 EXPORTED SUBROUTINES

C<Auto::Mata> is an C<Exporter>. All subroutines are exported by default.

=head2 machine

Creates a lexical context in which a state machine is defined. Returns a
function that creates new instances of the defined automata. The automata
instance itself is a function that performs a single transition per call,
returning the current state's label in scalar context, the label and state data
(the reference passed to the builder) in list context, and C<undef> after the
terminal state has been reached.

The reference value passed to the builder function holds the machine's
B<mutable> running state and is matched against L<Type::Tiny> type constraints
(see L</transition> and L</on>) to determine the next transition state.

  # Define the state machine
  my $builder = machine {
    ...
  };

  # Create an instance of the machine that operates on $state.
  my $program = $builder->(my $state = [...]);

  # Run the program
  while (my ($token, $data) = $program->()) {
    print "Current state is $token\n"; # $token == label of current state (e.g. READY)
    print "State data: @$data\n";      # $data == $state passed to builder
  }

=cut

sub machine (&) {
  my $code = shift;

  #-----------------------------------------------------------------------------
  # Define the machine parameters
  #-----------------------------------------------------------------------------
  my %map;
  my %fsm = (ready => undef, term => undef, map => \%map);

  do {
    local $_ = \%fsm;
    $code->();
    validate();
  };

foreach my $from (keys %map) {
  print "\nFROM $from\n";
  foreach my $to (keys %{$map{$from}}) {
    print " TO $to WHEN $map{$from}{$to}[0]\n";
  }
}

  #-----------------------------------------------------------------------------
  # Build the transition engine
  #-----------------------------------------------------------------------------
  my @match;
  foreach my $from (keys %map) {
    #---------------------------------------------------------------------------
    # Create type constraints for each "from" state to validate that the
    # machine's state is consistent after each transition.
    #---------------------------------------------------------------------------
    my @next_types;
    foreach my $to (keys %{$map{$from}}) {         # $to = each state $from can transition to
      foreach my $next (keys %{$map{$to}}) {       # $next = each state $to can transition to
        if ($next eq $fsm{term}) {                 # Termination matches any result since there
          push @next_types, Any;                   #   are no further states to validate against
        } else {
          push @next_types, $map{$to}{$next}->[0]; # Initial state constraints for each $next
        }
      }
    }

    my $next = declare "Next_State_After_$from", as @next_types
      ? reduce { $a | $b } @next_types
      : Any;

    #---------------------------------------------------------------------------
    # Create a type constraint that matches each possible initial "from" state.
    # Use this to build a matching function that calls the appropriate mutator
    # for that transisiton.
    #---------------------------------------------------------------------------
    foreach my $to (keys %{$map{$from}}) {
      my ($match, $on, $with) = @{$map{$from}{$to}};

      push @match, $match, sub {
        debug("%s -> %s: %s", $_->[0], $to, explain($_->[1]));
        my ($from, $data) = @$_;

        do { local $_ = $data; $data = $with->() };

        my $state = [$to, $data];

        if (defined(my $error = $next->validate($state))) {
          my @msg;
          push @msg, sprintf('Transition from %s to %s resulted in an invalid state.', $from, $to);
          push @msg, sprintf('Current state is: %s', explain($state));
          push @msg, sprintf('Type constraint returned an error: %s', $error);
          push(@msg, join "\n", map { " -$_" } @{$next->validate_explain($state, 'NEXT STATE')}) if $DEBUG;
          croak join("\n", @msg);
        }

        @$_ = @$state;
        return $state;
      };
    }
  }

  my $default   = sub { croak 'no transitions match ' . explain($_) };
  my $transform = compile_match_on_type(@match, => $default);
  my $terminal  = Tuple[Enum[$fsm{term}], Any];

  #-----------------------------------------------------------------------------
  # Return function that builds a transition engine for the given input
  #-----------------------------------------------------------------------------
  return sub {
    my $data  = \$_[0];
    my $state = [$fsm{ready}, $_[0]];
    my $done;

    sub {
      return if $done;
      $state = $transform->($state);
      $done  = $terminal->check($state);
      $$data = $state->[1];
      wantarray ? (@$state) : $state->[0];
    };
  };
}

=head2 ready

=head2 terminal

=head2 to

=head2 on

=head2 with

=cut

sub ready    ($)   { assert_in_the_machine(); $_->{ready} = shift }
sub terminal ($)   { assert_in_the_machine(); $_->{term}  = shift }
sub to       ($;%) { (to   => shift, @_) }
sub on       ($;%) { (on   => shift, @_) }
sub with     (&;%) { (with => shift, @_) }

=head2 transition

=cut

sub transition ($%) {
  assert_in_the_machine();
  state $check = compile($Ident, $Ident, $Type, $Code);

  my ($arg, %param) = @_;
  my ($from, $to, $on, $with) = $check->($arg, @param{qw(to on with)});

  croak "transition from state $from to $to is already defined"
    if exists $_->{map}{$from}{$to};

  my $name  = sprintf('%s_to_%s', $from, $to);
  my $match = declare $name, as Tuple[Enum[$from], $on];

  $_->{map}{$from} //= {};
  $_->{map}{$from}{$to} = [$match, $on, $with];
}

#-------------------------------------------------------------------------------
#
#-------------------------------------------------------------------------------
sub assert_in_the_machine {
  unless ($_ && !defined(my $msg = $Automata->validate_explain($_, '$_'))) {
    debug('Invalid machine state detected: %s', join("\n", map {"\t$_"} @$msg)) if $msg;
    croak 'cannot be called outside a state machine definition block';
  }
}

#-------------------------------------------------------------------------------
#
#-------------------------------------------------------------------------------
sub debug {
  return unless $DEBUG;
  my ($msg, @args) = @_;
  printf("DEBUG> $msg\n", @args);
}

#-------------------------------------------------------------------------------
#
#-------------------------------------------------------------------------------
sub explain {
  my $state = shift;
  local $Data::Dumper::Indent = 0;
  local $Data::Dumper::Terse  = 1;
  Dumper($state);
}

#-------------------------------------------------------------------------------
# Validate sanity as much as possible without strict types and without
# guarantees on the return type of transitions.
#-------------------------------------------------------------------------------
sub validate {
  $Automata->assert_valid($_);

  croak 'no ready state defined'
    unless $_->{ready};

  croak 'no terminal state defined'
    unless $_->{term};

  croak 'no transitions defined'
    unless keys %{$_->{map}};

  croak 'no transition defined for ready state'
    unless $_->{map}{$_->{ready}};

  my $is_terminated;

  foreach my $from (keys %{$_->{map}}) {
    croak 'invalid transition from terminal state detected'
      if $from eq $_->{term};

    foreach my $to (keys %{$_->{map}{$from}}) {
      if ($to eq $_->{term}) {
        $is_terminated = 1;
        next;
      }

      croak "no subsequent states are reachable from $to"
        unless exists $_->{map}{$to};
    }
  }

  croak 'no transition defined to terminal state'
    unless $is_terminated;
}

1;
