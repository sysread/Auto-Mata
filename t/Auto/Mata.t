use Test2::Bundle::Extended;
use Types::Standard -types;
use Type::Utils -all;
use Auto::Mata;

subtest 'positive path' => sub {
  my $Remaining = declare as ArrayRef[Num], where { @$_ > 1 };
  my $Reduced   = declare as ArrayRef[Num], where { @$_ == 1 };

  my $fsm = machine {
    ready 'READY';
    terminal 'TERM';

    transition 'READY', to 'REDUCE',
      on $Remaining;

    transition 'REDUCE', to 'REDUCE',
      on $Remaining,
      with { @$_ = (shift(@$_) + shift(@$_), @$_) };

    transition 'REDUCE', to 'TERM',
      on $Reduced;
  };

  my $arr = [1, 2, 3];
  my @states;
  my @results;

  ok $fsm, 'machine';
  ok my $adder = $fsm->($arr), 'builder';

  while (my ($state, $data) = $adder->()) {
    push @states, $state;
    push @results, [@$data];
    die "backstop reached" if @states > 10;
  }

  is \@states, [qw(REDUCE REDUCE REDUCE TERM)], 'expected state progression';
  is \@results, [[1, 2, 3], [3, 3], [6], [6]], 'expected result progression';
  is $arr, [6], 'expected result';
};

subtest 'sanity checks' => sub {
  like dies { machine { } }, qr/no ready state defined/, 'missing ready state';
  like dies { machine { ready 'READY' } }, qr/no terminal state defined/, 'missing terminal state';
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
