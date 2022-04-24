#!lib/test-in-container-environ.sh
set -eo pipefail

ng1=$(environ ng)
$ng1/start

mc=$(environ mc $(pwd))

$mc/gen_env MIRRORCACHE_ROOT=http://$($ng1/print_address) \
    MIRRORCACHE_STAT_FLUSH_COUNT=100 \
    MIRRORCACHE_WORKERS=4 \
    MIRRORCACHE_HYPNOTOAD=1

$mc/start
$mc/status

mkdir $ng1/dt/folder{1,2,3,4,5,6,7,8,9}
echo $ng1/dt/folder{1,2,3,4,5,6,7,8,9}/file1.1.dat | xargs -n 1 touch

for ((i=1; i<=9; i++)); do
    mkdir $ng1/dt/folder$i/subfolder{1,2,3,4,5,6,7,8,9}
    echo $ng1/dt/folder$i/subfolder{1,2,3,4,5,6,7,8,9}/file{1,2,3,4,5}.1.dat | xargs -n 1 touch
done

ap=($mc)
for ((i=1; i<=9; i++)); do
    x=$(environ ap$i)
    ap+=($x)
    $x/start
    cp -r $ng1/dt/* $x/dt/

    case $i in
      [1-3])
        country=us
        continent=na
        ;;
      [4-6])
        country=de
        continent=eu
        ;;
      *)
        country=jp
        continent=as
        ;;
    esac

    $mc/sql "insert into server(hostname,urldir,enabled,country,region) select '$($x/print_address)','','t','$country','$continent'"
done

for ((i=1; i<=9; i++)); do
    $mc/curl -IL /download/folder$i/file1.1.dat | grep $($ng1/print_address)
    $mc/backstage/job -e folder_sync -a '["/folder'$i'"]'
done

$mc/backstage/job mirror_scan_schedule
$mc/backstage/shoot

for ((i=1; i<=9; i++)); do
    $mc/curl -IL /download/folder$i/file1.1.dat            | grep -E "$(${ap[1]}/print_address)|$(${ap[2]}/print_address)|$(${ap[3]}/print_address)"
    $mc/curl -IL /download/folder$i/file1.1.dat?COUNTRY=de | grep -E "$(${ap[4]}/print_address)|$(${ap[5]}/print_address)|$(${ap[6]}/print_address)"
    $mc/curl -IL /download/folder$i/file1.1.dat?COUNTRY=jp | grep -E "$(${ap[7]}/print_address)|$(${ap[8]}/print_address)|$(${ap[9]}/print_address)"
done

[ ! -f requests.txt ] || rm requests.txt

for ((i=1; i<=9; i++)); do
    for ((j=1; j<=1; j++)); do
        for ((k=1; k<=1; k++)); do
            rnd=$(($RANDOM % 3))
            if [ $rnd = 0 ]; then
                P='?COUNTRY=de'
            elif [ $rnd == 1 ]; then
                P='?COUNTRY=jp'
            else
                P=''
            fi
            echo "$($mc/print_address)/download/folder$i/file$j.$k.dat$P" >> requests.txt
        done
    done
done

$mc/status


(
    sleep 2
    # start parallel threads discovering folders
    k=${1:-5}
    for ((i=1; i<=9; i++)); do
        for ((j=1; j<=9; j++)); do
            : $((k--))
            test $k -le 0 || ( set -x ; $mc/curl -i /download/folder$i/subfolder$j/ & ) # > /dev/null & )
        done
    done
)&


siege -f requests.txt -c 16  -t10s -i --no-follow --no-parser | grep -v 'HTTP/1.1 200' | grep -v 'HTTP/1.1 302' || :



sleep 20
