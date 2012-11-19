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

get '/' => sub {
    my $self = shift;

    my $teng = create_dbi();
    my $today = get_today();

    # 今月の出退勤で初期化
    my @kintai_source = ();
    {
        my @kintai_data = create_kintai_data( $today->{year}, $today->{mon} );
        my $ite = $teng->search(
              kintai => {
                year => $today->{year},
                mon  => $today->{mon}
            }
        );
        while ( my $row = $ite->next ) {
            my $data = $row->get_columns();
            $kintai_data[$data->{day}] = $data;
        }

        # 表示用の文字列を格納
        foreach my $data ( @kintai_data ) {
            my $src = {
                year        => $data->{year},
                mon         => $data->{mon},
                day         => $data->{day},
                label_begin => '00:00',
                label_end   => '00:00'
            };

            if ( $data->{time_begin} != 0 ) {
                my ( $sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst ) = localtime( $data->{time_begin} );
                $src->{label_begin} = sprintf( "%2d:%2d", $hour, $min );
            }

            if ( $data->{time_end} != 0 ) {
                my ( $sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst ) = localtime( $data->{time_end} );
                $src->{label_end} = sprintf( "%2d:%2d", $hour, $min );
            }

            push @kintai_source, $src;
        }
    }

    $self->app->log->debug( "day = " . $today->{day} );

    $self->stash( today => $today );
    $self->stash( kintai_source => \@kintai_source );

    $self->render( 'index' );
};

get '/begin' => sub {
    my $self = shift;
    update_kintai( 'time_begin' );
    $self->redirect_to( '/' );
};

get '/end' => sub {
    my $self = shift;
    update_kintai( 'time_end' );
    $self->redirect_to( '/' );
};

sub update_kintai {
    my $column = shift;

    my $teng = create_dbi();
    my $today = get_today();

#todo singleを使う
    my $ite = $teng->search(
        kintai => {
            year => $today->{year},
            mon  => $today->{mon},
            day  => $today->{day}
        }
    );

    my $row = $ite->next;
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

# 先頭にダミーデータが存在する、空の勤怠配列を返す
sub create_kintai_data {
    my ( $year, $mon ) = @_;
    my $cnt = calc_data_count( $year, $mon );

    # +{}を使う例
    return map +{
            year       => $year,
            mon        => $mon,
            day        => $_,
            time_begin => 0,
            time_end   => 0
    },
    0..$cnt;
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
__DATA__

@@ index.html.ep
% layout 'default';
% title sprintf( "%4d/%02d", $today->{year}, $today->{mon} );
<h1>Tengで作った勤怠管理システム</h1>
<section>
  <h2><%= $today->{year} %>/<%= $today->{mon} %>/<%= $today->{day} %></h2>
  <p>
    <a href="./begin">出社</a> | <a href="./end">退勤</a>
  </p>
</section>
<section>
  <table>
    <tr>
      <th>月</th><th>日</th><th>出勤</th><th>退勤</th>
    </tr>
    <tr>
% for my $src (@$kintai_source) {
%     # 先頭のダミーデータは無視
%     if ( $src->{day} == 0 ) { next; }
%     elsif ( $src->{day} == $today->{day} ) {
    <tr class="today">
%     }
%     else {
    <tr>
%     }
      <td><%= $src->{mon} %></td><td><%= $src->{day} %></td><td><%= $src->{label_begin} %></td><td><%= $src->{label_end} %></td>
    </tr>
% }
  </table>
</section>

@@ layouts/default.html.ep
<!DOCTYPE html>
<html>
  <head>
    <meta charset="utf-8">
    <title><%= title %></title>
    <style type="text/css">
<!--
body, h1, h2, h3, h4, h5, h6, blockquote, p, form{
    margin: 0;
    padding: 0;
}

h1 {
    font-size: 1.2em;
    margin: 10px 20px;
}

section {
    margin: 10px 20px;  
}
h2 {
    font-size: 1.0em;
}
p {
    font-size: 0.8em;
}
table {
    border: 1px #999 solid;
    border-collapse: collapse;
    border-spacing: 0;
}
table tr {
    margin: 0;
    padding: 0;
}
table th {
    font-size: 0.8em;
    padding: 3px 4px 1px 4px;
    border: #999 solid;
    border-width: 1px;
    background: #ccc;
    font-weight: bold;
    text-align: center;
}
table td {
    font-size: 0.8em;
    padding: 3px 4px 1px 4px;
    border: 1px #999 solid;
    border-width: 1px;
    text-align: right;
}
table tr.today td {
    background-color: #fcc;
}
    </style>
  </head>
  <body>
    <%= content %>
  </body>
</html>
