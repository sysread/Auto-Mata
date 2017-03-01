use Test2::Bundle::Extended;
use Types::Standard -types;
use Type::Utils -all;
use Auto::Mata;

subtest 'basics' => sub {
  my $PosInt    = declare as Int, where { $_ > 0 };
  my $Remaining = declare as ArrayRef[$PosInt], where { @$_ > 1 };
  my $Reduced   = declare as ArrayRef[$PosInt], where { @$_ == 1 };

  my $fsm = machine {
    ready 'READY';
    terminal 'TERM';

    transition 'READY', to 'REDUCE',
      on $Remaining;

    transition 'REDUCE', to 'REDUCE',
      on $Remaining,
      with { [(shift(@$_) + shift(@$_)), @$_] };

    transition 'REDUCE', to 'TERM',
      on $Reduced;

    # Purposefully return a result that will not match any other transitions.
    transition 'READY', to 'UNDEF',  on Undef, with { [1, 2, 'three'] };
    transition 'UNDEF', to 'REDUCE', on Any;
  };

  ok $fsm, 'machine';
  ok my $adder = $fsm->(), 'instance';

  my $arr = [1, 2, 3];
  my @states;
  my @results;

  while (my ($state, $data) = $adder->($arr)) {
    is $data, $arr, 'returns reference to input';
    push @states, $state;
    push @results, [@$data];
    die "backstop reached" if @states > 10;
  }

  is \@states, [qw(REDUCE REDUCE REDUCE TERM)], 'expected state progression';
  is \@results, [[1, 2, 3], [3, 3], [6], [6]], 'expected result progression';
  is $arr, [6], 'accumulator contains expected result';

  like dies { $fsm->()->([1, 2, -5]) }, qr/no transitions match/, 'expected error on invalid input type';

  my $fails = $fsm->();
  my $undef;
  is [$fails->($undef)], ['UNDEF', [1, 2, 'three']], 'setup for failure 1';
  is [$fails->($undef)], ['REDUCE', [1, 2, 'three']], 'setup for failure 2';
  like dies { $fails->($undef) }, qr/no transitions match/, 'expected error on match failure';
};

subtest 'sanity checks' => sub {
  like dies { transition 'READY' }, qr/cannot be called outside a state machine definition block/, 'transition outside the machine';
  like dies { ready 'READY' }, qr/cannot be called outside a state machine definition block/, 'ready outside the machine';
  like dies { terminal 'TERM' }, qr/cannot be called outside a state machine definition block/, 'terminal outside the machine';

  like dies { machine { } }, qr/no ready state defined/, 'missing ready state';
  like dies { machine { ready 'READY' } }, qr/no terminal state defined/, 'missing terminal state';
  like dies { machine { ready 'READY'; terminal 'READY' } }, qr/terminal state and ready state are identical/, 'terminal eq ready state';
  like dies { machine { ready 'READY'; terminal 'TERM' } }, qr/no transitions defined/, 'missing transitions';

  like dies {
    machine {
      ready 'READY'; terminal 'TERM';
      transition 'FOO', to 'TERM', on Any;
    };
  }, qr/no transition defined for ready state/, 'no ready transition';

  like dies {
    machine {
      ready 'READY'; terminal 'TERM';
      transition 'READY', to 'FOO', on Any;
      transition 'FOO', to 'READY', on Any;
    };
  }, qr/no transition defined to terminal state/, 'no terminal transition';

  like dies {
    machine {
      ready 'READY'; terminal 'TERM';
      transition 'READY', to 'FOO', on Any;
    };
  }, qr/no subsequent states are reachable from FOO/, 'incomplete (dangling state)';

  like dies {
    machine {
      ready 'READY'; terminal 'TERM';
      transition 'READY', to 'FOO', on Any;
      transition 'FOO', to 'TERM', on Any;
      transition 'TERM', to 'READY', on Any;
    };
  }, qr/invalid transition from terminal state detected/, 'invalid terminal state transition';
};

done_testing;
