#!/usr/bin/env perl
package Your::DB::Schema;
use Teng::Schema::Declare;

table {
    name 'kintai';
    pk 'idx';
    columns qw( idx year mon day time_begin time_end );
};

package Your::DB;
use parent 'Teng';

package main;
use Mojolicious::Lite;

use Teng;
use Data::Dumper;

use utf8;

# Documentation browser under "/perldoc"
plugin 'PODRenderer';

get '/:file' => { file => 'index.html' } => sub {
    my $self = shift;

    my $today = get_today();

    # 今月の出退勤で初期化
    my @kintai_source = create_kintai_source( $today->{year}, $today->{mon} );

    $self->app->log->debug(
        sprintf("Date: %4d/%2d/%2d", $today->{year}, $today->{mon}, $today->{day}) );

    $self->stash( today  => $today          );
    $self->stash( year   => $today->{year}  );
    $self->stash( mon    => $today->{mon}   );
    $self->stash( day    => $today->{day}   );
    $self->stash( kintai => \@kintai_source );

    $self->render( 'index' );
};

get '/action/begin' => sub {
    my $self = shift;
    update_kintai( 'time_begin' );
    $self->redirect_to( '/' );
};

get '/action/end' => sub {
    my $self = shift;
    update_kintai( 'time_end' );
    $self->redirect_to( '/' );
};

get '/api/list/:year/:mon' => sub {
    my $self = shift;

    my $YY = ( $self->param('year')  =~ /((\d){4})/ ) ? int($1) : undef;
    my $MM = ( $self->param('mon')   =~ /((\d){2})/ ) ? int($1) : undef;

    # todo: 月が1〜12であることをチェックする

    if ( !$YY or !$MM ) {
        $self->render(
            json => { text => 'Oops.' },
            status => 403
        );
    }
    else {
        my @kintai_source = create_kintai_source( $YY, $MM );
        $self->render(
            json => {
                year    => $YY,
                mon     => $MM,
                kintai  => \@kintai_source
            }
        );
    }
};

sub create_kintai_source {
    my ( $year, $mon ) = @_;
    my $cnt = calc_data_count( $year, $mon );

    # 先頭にダミーデータが存在する、空の勤怠配列を作る
    # +{}を使う例
    my @kintai_data = map +{
        day        => $_,
        time_begin => 0,
        time_end   => 0
    }, 0..$cnt;

    # 存在する勤怠データで初期化
    my $teng = create_dbi();
    my $ite = $teng->search(
        kintai => {
            year => $year,
            mon  => $mon
        }
    );
    while ( my $row = $ite->next ) {
        my $data = $row->get_columns();
        $kintai_data[$data->{day}] = $data;
    }

    # 先頭のダミーデータを破棄
    shift @kintai_data;

    # 表示用の勤怠データ配列を生成
    my @kintai_source = ();
    foreach my $data ( @kintai_data ) {
        my $src = {
            day         => $data->{day},
            label_begin => '00:00',
            label_end   => '00:00'
        };

        if ( $data->{time_begin} != 0 ) {
            my ( $sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst ) = localtime( $data->{time_begin} );
            $src->{label_begin} = sprintf( "%02d:%02d", $hour, $min );
        }

        if ( $data->{time_end} != 0 ) {
            my ( $sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst ) = localtime( $data->{time_end} );
            $src->{label_end} = sprintf( "%02d:%02d", $hour, $min );
        }

        push @kintai_source, $src;
    }

    return @kintai_source;
}

sub update_kintai {
    my $column = shift;

    my $teng = create_dbi();
    my $today = get_today();

    my $row = $teng->single(
        kintai => {
            year => $today->{year},
            mon  => $today->{mon},
            day  => $today->{day}
        }
    );

    if ( $row ) {
        $row->update(
            { $column => $today->{raw} }
        );
    }
    else {
        $row = $teng->insert(
            kintai => {
                year => $today->{year},
                mon  => $today->{mon},
                day  => $today->{day},
                $column => $today->{raw}
            }
        );
    }
}

sub create_dbi {
    my $db_file = './kintai.db';
    my $exists_db = ( -e $db_file );

    my $teng = Your::DB->new(
        +{
            connect_info => [
                'dbi:SQLite:' . $db_file,
                '',
                ''
            ]
        }
    );

    if ( not $exists_db ) {
        $teng->do(
            q{
                CREATE TABLE   kintai (
                idx INTEGER PRIMARY KEY,
                year INTEGER UNSIGNED DEFAULT 0,
                mon INTEGER UNSIGNED DEFAULT 0,
                day INTEGER UNSIGNED DEFAULT 0,
                time_begin INTEGER UNSIGNED DEFAULT 0,
                time_end INTEGER UNSIGNED DEFAULT 0
                )
            }
        );
    }

    return $teng;
}

sub calc_data_count {
    my ( $year, $mon ) = @_;

    my @tmp = grep { $_ == $mon } ( 2, 4, 6, 9, 11 );
    if ( 0 < scalar(@tmp) ) {
        if ( $mon == 2 ) {
            # 400で割り切れるか、100で割り切れず4で割り切れたら閏年
            if (  ($year % 400) == 0
              or (($year % 100) != 0 and ($year % 4) == 0) ) {
                return 29;
            }
            else {
                return 28;
            }
        }
        else {
            return 30;
        }
    }
    else {
        return 31;
    }
}

# 今日の年/月/日を算出
sub get_today {
    my $time_now = time;
    my ( $sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst ) = localtime( $time_now );
    return {
        year => $year + 1900,
        mon  => $mon + 1,
        day  => $mday,
        raw  => $time_now
    };
}

app->start;

__END__