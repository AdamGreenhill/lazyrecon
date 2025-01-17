#!/bin/bash


########################################
# ///                                        \\\
#     You can edit your configuration here
#
#
########################################
auquatoneThreads=5
subdomainThreads=10
dirsearchThreads=50
dirsearchWordlist=/opt/tools/dirsearch/db/dicc.txt
massdnsWordlist=/opt/tools/SecLists/Discovery/DNS/clean-jhaddix-dns.txt
outfile=/output
########################################
# Happy Hunting
########################################






red=`tput setaf 1`
green=`tput setaf 2`
yellow=`tput setaf 3`
reset=`tput sgr0`

SECONDS=0

domain=
subreport=
usage() { echo -e "Usage: ./lazyrecon.sh -d domain.com [-e] [excluded.domain.com,other.domain.com]\nOptions:\n  -e\t-\tspecify excluded subdomains\n " 1>&2; exit 1; }

while getopts ":d:e:r:" o; do
    case "${o}" in
        d)
            domain=${OPTARG}
            ;;

            #### working on subdomain exclusion
        e)
            set -f
      IFS=","
      excluded+=($OPTARG)
      unset IFS
            ;;

    r)
            subreport+=("$OPTARG")
            ;;
        *)
            usage
            ;;
    esac
done
shift $((OPTIND - 1))

if [ -z "${domain}" ] && [[ -z ${subreport[@]} ]]; then
   usage; exit 1;
fi

discovery(){
  hostalive $domain
  cleandirsearch $domain
  aqua $domain
  cleanup $domain
  waybackrecon $domain
  dirsearcher
}

waybackrecon () {
echo "Scraping wayback for data..."
cat $outfile/$domain/$foldername/urllist.txt | waybackurls > $outfile/$domain/$foldername/wayback-data/waybackurls.txt
cat $outfile/$domain/$foldername/wayback-data/waybackurls.txt  | sort -u | unfurl --unique keys > $outfile/$domain/$foldername/wayback-data/paramlist.txt
[ -s $outfile/$domain/$foldername/wayback-data/paramlist.txt ] && echo "Wordlist saved to $outfile/$domain/$foldername/wayback-data/paramlist.txt"

cat $outfile/$domain/$foldername/wayback-data/waybackurls.txt  | sort -u | grep -P "\w+\.js(\?|$)" | sort -u > $outfile/$domain/$foldername/wayback-data/jsurls.txt
[ -s $outfile/$domain/$foldername/wayback-data/jsurls.txt ] && echo "JS Urls saved to $outfile/$domain/$foldername/wayback-data/jsurls.txt"

cat $outfile/$domain/$foldername/wayback-data/waybackurls.txt  | sort -u | grep -P "\w+\.php(\?|$) | sort -u " > $outfile/$domain/$foldername/wayback-data/phpurls.txt
[ -s $outfile/$domain/$foldername/wayback-data/phpurls.txt ] && echo "PHP Urls saved to $outfile/$domain/$foldername/wayback-data/phpurls.txt"

cat $outfile/$domain/$foldername/wayback-data/waybackurls.txt  | sort -u | grep -P "\w+\.aspx(\?|$) | sort -u " > $outfile/$domain/$foldername/wayback-data/aspxurls.txt
[ -s $outfile/$domain/$foldername/wayback-data/aspxurls.txt ] && echo "ASP Urls saved to $outfile/$domain/$foldername/wayback-data/aspxurls.txt"

cat $outfile/$domain/$foldername/wayback-data/waybackurls.txt  | sort -u | grep -P "\w+\.jsp(\?|$) | sort -u " > $outfile/$domain/$foldername/wayback-data/jspurls.txt
[ -s $outfile/$domain/$foldername/wayback-data/jspurls.txt ] && echo "JSP Urls saved to $outfile/$domain/$foldername/wayback-data/jspurls.txt"
}

cleanup(){
  cd $outfile/$domain/$foldername/screenshots/
  rename 's/_/-/g' -- *

  cd $path
}

hostalive(){
echo "Probing for live hosts..."
cat $outfile/$domain/$foldername/alldomains.txt | sort -u | httprobe -c 50 -t 3000 >> $outfile/$domain/$foldername/responsive.txt
cat $outfile/$domain/$foldername/responsive.txt | sed 's/\http\:\/\///g' |  sed 's/\https\:\/\///g' | sort -u | while read line; do
probeurl=$(cat $outfile/$domain/$foldername/responsive.txt | sort -u | grep -m 1 $line)
echo "$probeurl" >> $outfile/$domain/$foldername/urllist.txt
done
echo "$(cat $outfile/$domain/$foldername/urllist.txt | sort -u)" > $outfile/$domain/$foldername/urllist.txt
echo  "${yellow}Total of $(wc -l $outfile/$domain/$foldername/urllist.txt | awk '{print $1}') live subdomains were found${reset}"
}

recon(){

  echo "${green}Recon started on $domain ${reset}"
  echo "Listing subdomains using sublister..."
  python /opt/tools/Sublist3r/sublist3r.py -d $domain -t 10 -v -o $outfile/$domain/$foldername/$domain.txt > /dev/null
  echo "Checking certspotter..."
  curl -s https://certspotter.com/api/v0/certs\?domain\=$domain | jq '.[].dns_names[]' | sed 's/\"//g' | sed 's/\*\.//g' | sort -u | grep $domain >> $outfile/$domain/$foldername/$domain.txt
  nsrecords $domain
  #excludedomains
  echo "Starting discovery..."
  discovery $domain
  cat $outfile/$domain/$foldername/$domain.txt | sort -u > $outfile/$domain/$foldername/$domain.txt

}

excludedomains(){
  # from @incredincomp with love <3
  echo "Excluding domains (if you set them with -e)..."
  IFS=$'\n'
  # prints the $excluded array to excluded.txt with newlines 
  printf "%s\n" "${excluded[*]}" > $outfile/$domain/$foldername/excluded.txt
  # this form of grep takes two files, reads the input from the first file, finds in the second file and removes
  grep -vFf $outfile/$domain/$foldername/excluded.txt $outfile/$domain/$foldername/alldomains.txt > $outfile/$domain/$foldername/alldomains2.txt
  mv $outfile/$domain/$foldername/alldomains2.txt $outfile/$domain/$foldername/alldomains.txt
  #rm $outfile/$domain/$foldername/excluded.txt # uncomment to remove excluded.txt, I left for testing purposes
  echo "Subdomains that have been excluded from discovery:"
  printf "%s\n" "${excluded[@]}"
  unset IFS
}

dirsearcher(){

echo "Starting dirsearch..."
cat $outfile/$domain/$foldername/urllist.txt | xargs -P$subdomainThreads -I % sh -c "python3 /opt/tools/dirsearch/dirsearch.py -e php,asp,aspx,jsp,html,zip,jar -w $dirsearchWordlist -t $dirsearchThreads -u % | grep Target && tput sgr0 && /opt/lazyrecon/lazyrecon.sh -r $domain -r $foldername -r %"
}

aqua(){
echo "Starting aquatone scan..."
cat $outfile/$domain/$foldername/urllist.txt | /opt/tools/aquatone -out $outfile/$domain/$foldername/aqua_out -threads $auquatoneThreads -silent
}

searchcrtsh(){
 /opt/tools/massdns/scripts/ct.py $domain 2>/dev/null > $outfile/$domain/$foldername/tmp.txt
 [ -s $outfile/$domain/$foldername/tmp.txt ] && cat $outfile/$domain/$foldername/tmp.txt | /opt/tools/massdns/bin/massdns -r /opt/tools/massdns/lists/resolvers.txt -t A -q -o S -w  $outfile/$domain/$foldername/crtsh.txt
 cat $outfile/$domain/$foldername/$domain.txt | /opt/tools/massdns/bin/massdns -r /opt/tools/massdns/lists/resolvers.txt -t A -q -o S -w  $outfile/$domain/$foldername/domaintemp.txt
}

mass(){
 python3 /opt/tools/massdns/scripts/subbrute.py $massdnsWordlist $domain | /opt/tools/massdns/bin/massdns -r /opt/tools/massdns/lists/resolvers.txt -t A -q -o S | grep -v 142.54.173.92 > $outfile/$domain/$foldername/mass.txt
}
nsrecords(){
                echo "Checking http://crt.sh"
                searchcrtsh $domain
                echo "Starting Massdns Subdomain discovery this may take a while"
                mass $domain > /dev/null
                echo "Massdns finished..."
                echo "${green}Started dns records check...${reset}"
                echo "Looking into CNAME Records..."


                cat $outfile/$domain/$foldername/mass.txt >> $outfile/$domain/$foldername/temp.txt
                cat $outfile/$domain/$foldername/domaintemp.txt >> $outfile/$domain/$foldername/temp.txt
                cat $outfile/$domain/$foldername/crtsh.txt >> $outfile/$domain/$foldername/temp.txt


                cat $outfile/$domain/$foldername/temp.txt | awk '{print $3}' | sort -u | while read line; do
                wildcard=$(cat $outfile/$domain/$foldername/temp.txt | grep -m 1 $line)
                echo "$wildcard" >> $outfile/$domain/$foldername/cleantemp.txt
                done



                cat $outfile/$domain/$foldername/cleantemp.txt | grep CNAME >> $outfile/$domain/$foldername/cnames.txt
                cat $outfile/$domain/$foldername/cnames.txt | sort -u | while read line; do
                hostrec=$(echo "$line" | awk '{print $1}')
                if [[ $(host $hostrec | grep NXDOMAIN) != "" ]]
                then
                echo "${red}Check the following domain for NS takeover:  $line ${reset}"
                echo "$line" >> $outfile/$domain/$foldername/pos.txt
                else
                echo -ne "working on it...\r"
                fi
                done
                sleep 1
                cat $outfile/$domain/$foldername/$domain.txt > $outfile/$domain/$foldername/alldomains.txt
                cat $outfile/$domain/$foldername/cleantemp.txt | awk  '{print $1}' | while read line; do
                x="$line"
                echo "${x%?}" >> $outfile/$domain/$foldername/alldomains.txt
                done
                sleep 1

}

report(){
  subdomain=$(echo $subd | sed 's/\http\:\/\///g' |  sed 's/\https\:\/\///g')
  echo "${yellow} [+] Generating report for $subdomain"

   cat $outfile/$domain/$foldername/aqua_out/aquatone_session.json | jq --arg v "$subd" -r '.pages[$v].headers[] | keys[] as $k | "\($k), \(.[$k])"' | grep -v "decreasesSecurity\|increasesSecurity" >> $outfile/$domain/$foldername/aqua_out/parsedjson/$subdomain.headers
  dirsearchfile=$(ls /opt/tools/dirsearch/reports/$subdomain/ | grep -v old)

  touch $outfile/$domain/$foldername/reports/$subdomain.html
  echo '<html><meta http-equiv="Content-Type" content="text/html; charset=UTF-8">
<meta http-equiv="X-UA-Compatible" content="IE=edge">' >> $outfile/$domain/$foldername/reports/$subdomain.html
  echo "<head>" >> $outfile/$domain/$foldername/reports/$subdomain.html
  echo "<title>Recon Report for $subdomain</title>
<style>.status.fourhundred{color:#00a0fc}
.status.redirect{color:#d0b200}.status.fivehundred{color:#DD4A68}.status.jackpot{color:#0dee00}.status.weird{color:#cc00fc}img{padding:5px;width:360px}img:hover{box-shadow:0 0 2px 1px rgba(0,140,186,.5)}pre{font-family:Inconsolata,monospace}pre{margin:0 0 20px}pre{overflow-x:auto}article,header,img{display:block}#wrapper:after,.blog-description:after,.clearfix:after{content:}.container{position:relative}html{line-height:1.15;-ms-text-size-adjust:100%;-webkit-text-size-adjust:100%}h1{margin:.67em 0}h1,h2{margin-bottom:20px}a{background-color:transparent;-webkit-text-decoration-skip:objects;text-decoration:none}.container,table{width:100%}.site-header{overflow:auto}.post-header,.post-title,.site-header,.site-title,h1,h2{text-transform:uppercase}p{line-height:1.5em}pre,table td{padding:10px}h2{padding-top:40px;font-weight:900}a{color:#00a0fc}body,html{height:100%}body{margin:0;background:#fefefe;color:#424242;font-family:Raleway,-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Oxygen,Ubuntu,'Helvetica Neue',Arial,sans-serif;font-size:24px}h1{font-size:35px}h2{font-size:28px}p{margin:0 0 30px}pre{background:#f1f0ea;border:1px solid #dddbcc;border-radius:3px;font-size:16px}.row{display:flex}.column{flex:100%}table tbody>tr:nth-child(odd)>td,table tbody>tr:nth-child(odd)>th{background-color:#f7f7f3}table th{padding:0 10px 10px;text-align:left}.post-header,.post-title,.site-header{text-align:center}table tr{border-bottom:1px dotted #aeadad}::selection{background:#fff5b8;color:#000;display:block}::-moz-selection{background:#fff5b8;color:#000;display:block}.clearfix:after{display:table;clear:both}.container{max-width:100%}#wrapper{height:auto;min-height:100%;margin-bottom:-265px}#wrapper:after{display:block;height:265px}.site-header{padding:40px 0 0}.site-title{float:left;font-size:14px;font-weight:600;margin:0}.site-title a{float:left;background:#00a0fc;color:#fefefe;padding:5px 10px 6px}.post-container-left{width:49%;float:left;margin:auto}.post-container-right{width:49%;float:right;margin:auto}.post-header{border-bottom:1px solid #333;margin:0 0 50px;padding:0}.post-title{font-size:55px;font-weight:900;margin:15px 0}.blog-description{color:#aeadad;font-size:14px;font-weight:600;line-height:1;margin:25px 0 0;text-align:center}.single-post-container{margin-top:50px;padding-left:15px;padding-right:15px;box-sizing:border-box}body.dark{background-color:#1e2227;color:#fff}body.dark pre{background:#282c34}body.dark table tbody>tr:nth-child(odd)>td,body.dark table tbody>tr:nth-child(odd)>th{background:#282c34} table tbody>tr:nth-child(even)>th{background:#1e2227} input{font-family:Inconsolata,monospace} body.dark .status.redirect{color:#ecdb54} body.dark input{border:1px solid ;border-radius: 3px; background:#282c34;color: white} body.dark label{color:#f1f0ea} body.dark pre{color:#fff}</style>
<script>
document.addEventListener('DOMContentLoaded', (event) => {
  ((localStorage.getItem('mode') || 'dark') === 'dark') ? document.querySelector('body').classList.add('dark') : document.querySelector('body').classList.remove('dark')
})
</script>" >> $outfile/$domain/$foldername/reports/$subdomain.html
echo '<link rel="stylesheet" type="text/css" href="https://cdnjs.cloudflare.com/ajax/libs/material-design-lite/1.1.0/material.min.css">
<link rel="stylesheet" type="text/css" href="https://cdn.datatables.net/1.10.19/css/dataTables.material.min.css">
  <script type="text/javascript" src="https://code.jquery.com/jquery-3.3.1.js"></script>
<script type="text/javascript" charset="utf8" src="https://cdn.datatables.net/1.10.19/js/jquery.dataTables.js"></script><script type="text/javascript" charset="utf8" src="https://cdn.datatables.net/1.10.19/js/dataTables.material.min.js"></script>'>> $outfile/$domain/$foldername/reports/$subdomain.html
echo '<script>$(document).ready( function () {
    $("#myTable").DataTable({
        "paging":   true,
        "ordering": true,
        "info":     true,
       "autoWidth": true,
            "columns": [{ "width": "5%" },{ "width": "5%" },null],
                "lengthMenu": [[10, 25, 50,100, -1], [10, 25, 50,100, "All"]],

    });
} );</script></head>'>> $outfile/$domain/$foldername/reports/$subdomain.html

echo '<body class="dark"><header class="site-header">
<div class="site-title"><p>' >> $outfile/$domain/$foldername/reports/$subdomain.html
echo "<a style=\"cursor: pointer\" onclick=\"localStorage.setItem('mode', (localStorage.getItem('mode') || 'dark') === 'dark' ? 'bright' : 'dark'); localStorage.getItem('mode') === 'dark' ? document.querySelector('body').classList.add('dark') : document.querySelector('body').classList.remove('dark')\" title=\"Switch to light or dark theme\">🌓 Light|dark mode</a>
</p>
</div>
</header>" >> $outfile/$domain/$foldername/reports/$subdomain.html
echo '<div id="wrapper"><div id="container">'  >> $outfile/$domain/$foldername/reports/$subdomain.html
echo "<h1 class=\"post-title\" itemprop=\"name headline\">Recon Report for <a href=\"http://$subdomain\">$subdomain</a></h1>" >> $outfile/$domain/$foldername/reports/$subdomain.html
echo "<p class=\"blog-description\">Generated by LazyRecon on $(date) </p>" >> $outfile/$domain/$foldername/reports/$subdomain.html
echo '<div class="container single-post-container">
<article class="post-container-left" itemscope="" itemtype="http://schema.org/BlogPosting">
<header class="post-header">
</header>
<div class="post-content clearfix" itemprop="articleBody">
<h2>Content Discovery</h2>' >> $outfile/$domain/$foldername/reports/$subdomain.html



  echo "<table id='myTable' class='stripe'>" >> $outfile/$domain/$foldername/reports/$subdomain.html
  echo "<thead><tr>
 <th>Status Code</th>
 <th>Content-Length</th>
 <th>Url</th>
 </tr></thead><tbody>" >> $outfile/$domain/$foldername/reports/$subdomain.html

   cat /opt/tools/dirsearch/reports/$subdomain/$dirsearchfile | while read nline; do
  status_code=$(echo "$nline" | awk '{print $1}')
  size=$(echo "$nline" | awk '{print $2}')
  url=$(echo "$nline" | awk '{print $3}')
  path=${url#*[0-9]/}
 echo "<tr>" >> $outfile/$domain/$foldername/reports/$subdomain.html
 if [[ "$status_code" == *20[012345678]* ]]; then
    echo "<td class='status jackpot'>$status_code</td><td class='status jackpot'>$size</td><td><a class='status jackpot' href='$url'>/$path</a></td>" >> $outfile/$domain/$foldername/reports/$subdomain.html
  elif [[ "$status_code" == *30[012345678]* ]]; then
    echo "<td class='status redirect'>$status_code</td><td class='status redirect'>$size</td><td><a class='status redirect' href='$url'>/$path</a></td>" >> $outfile/$domain/$foldername/reports/$subdomain.html
  elif [[ "$status_code" == *40[012345678]* ]]; then
    echo "<td class='status fourhundred'>$status_code</td><td class='status fourhundred'>$size</td><td><a class='status fourhundred' href='$url'>/$path</a></td>" >> $outfile/$domain/$foldername/reports/$subdomain.html
  elif [[ "$status_code" == *50[012345678]* ]]; then
    echo "<td class='status fivehundred'>$status_code</td><td class='status fivehundred'>$size</td><td><a class='status fivehundred' href='$url'>/$path</a></td>" >> $outfile/$domain/$foldername/reports/$subdomain.html
  else
     echo "<td class='status weird'>$status_code</td><td class='status weird'>$size</td><td><a class='status weird' href='$url'>/$path</a></td>" >> $outfile/$domain/$foldername/reports/$subdomain.html
  fi
 echo "</tr>">> $outfile/$domain/$foldername/reports/$subdomain.html
done

  echo "</tbody></table></div>" >> $outfile/$domain/$foldername/reports/$subdomain.html

echo '</article><article class="post-container-right" itemscope="" itemtype="http://schema.org/BlogPosting">
<header class="post-header">
</header>
<div class="post-content clearfix" itemprop="articleBody">
<h2>Screenshots</h2>
<pre style="max-height: 340px;overflow-y: scroll">' >> $outfile/$domain/$foldername/reports/$subdomain.html
echo '<div class="row">
<div class="column">
Port 80' >> $outfile/$domain/$foldername/reports/$subdomain.html
scpath=$(echo "$subdomain" | sed 's/\./_/g')
httpsc=$(ls $outfile/$domain/$foldername/aqua_out/screenshots/http__$scpath* 2>/dev/null)
echo "<a href=\"../aqua_out/screenshots/${httpsc##*/}\"><img/src=\"../aqua_out/screenshots/${httpsc##*/}\"></a> " >> $outfile/$domain/$foldername/reports/$subdomain.html
echo '</div>
  <div class="column">
Port 443' >> $outfile/$domain/$foldername/reports/$subdomain.html
httpssc=$(ls $outfile/$domain/$foldername/aqua_out/screenshots/https__$scpath* 2>/dev/null)
echo "<a href=\"../aqua_out/screenshots/${httpsc##*/}\"><img/src=\"../aqua_out/screenshots/${httpsc##*/}\"></a>" >> $outfile/$domain/$foldername/reports/$subdomain.html
echo "</div></div></pre>" >> $outfile/$domain/$foldername/reports/$subdomain.html
#echo "<h2>Dig Info</h2><pre>$(dig $subdomain)</pre>" >> $outfile/$domain/$foldername/reports/$subdomain.html
echo "<h2>Host Info</h2><pre>$(host $subdomain)</pre>" >> $outfile/$domain/$foldername/reports/$subdomain.html
echo "<h2>Response Headers</h2><pre>" >> $outfile/$domain/$foldername/reports/$subdomain.html




cat $outfile/$domain/$foldername/aqua_out/parsedjson/$subdomain.headers | while read ln;do
check=$(echo "$ln" | awk '{print $1}')

[ "$check" = "name," ] && echo -n "$ln : " | sed 's/name, //g' >> $outfile/$domain/$foldername/reports/$subdomain.html
[ "$check" = "value," ] && echo " $ln" | sed 's/value, //g' >> $outfile/$domain/$foldername/reports/$subdomain.html

done



echo "</pre>" >> $outfile/$domain/$foldername/reports/$subdomain.html
echo "<h2>NMAP Results</h2>
<pre>
$(nmap -sV -T3 -Pn -p- $subdomain  |  grep -E 'open|filtered|closed')
</pre>
</div></article></div>
</div></div></body></html>" >> $outfile/$domain/$foldername/reports/$subdomain.html


}

master_report()
{

#this code will generate the html report for target it will have an overview of the scan
  echo '<html>
<head><meta http-equiv="Content-Type" content="text/html; charset=UTF-8">
<meta http-equiv="X-UA-Compatible" content="IE=edge">' >> $outfile/$domain/$foldername/master_report.html
echo "<title>Recon Report for $domain</title>
<style>.status.redirect{color:#d0b200}.status.fivehundred{color:#DD4A68}.status.jackpot{color:#0dee00}img{padding:5px;width:360px}img:hover{box-shadow:0 0 2px 1px rgba(0,140,186,.5)}pre{font-family:Inconsolata,monospace}pre{margin:0 0 20px}pre{overflow-x:auto}article,header,img{display:block}#wrapper:after,.blog-description:after,.clearfix:after{content:}.container{position:relative}html{line-height:1.15;-ms-text-size-adjust:100%;-webkit-text-size-adjust:100%}h1{margin:.67em 0}h1,h2{margin-bottom:20px}a{background-color:transparent;-webkit-text-decoration-skip:objects;text-decoration:none}.container,table{width:100%}.site-header{overflow:auto}.post-header,.post-title,.site-header,.site-title,h1,h2{text-transform:uppercase}p{line-height:1.5em}pre,table td{padding:10px}h2{padding-top:40px;font-weight:900}a{color:#00a0fc}body,html{height:100%}body{margin:0;background:#fefefe;color:#424242;font-family:Raleway,-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Oxygen,Ubuntu,'Helvetica Neue',Arial,sans-serif;font-size:24px}h1{font-size:35px}h2{font-size:28px}p{margin:0 0 30px}pre{background:#f1f0ea;border:1px solid #dddbcc;border-radius:3px;font-size:16px}.row{display:flex}.column{flex:100%}table tbody>tr:nth-child(odd)>td,table tbody>tr:nth-child(odd)>th{background-color:#f7f7f3}table th{padding:0 10px 10px;text-align:left}.post-header,.post-title,.site-header{text-align:center}table tr{border-bottom:1px dotted #aeadad}::selection{background:#fff5b8;color:#000;display:block}::-moz-selection{background:#fff5b8;color:#000;display:block}.clearfix:after{display:table;clear:both}.container{max-width:100%}#wrapper{height:auto;min-height:100%;margin-bottom:-265px}#wrapper:after{display:block;height:265px}.site-header{padding:40px 0 0}.site-title{float:left;font-size:14px;font-weight:600;margin:0}.site-title a{float:left;background:#00a0fc;color:#fefefe;padding:5px 10px 6px}.post-container-left{width:49%;float:left;margin:auto}.post-container-right{width:49%;float:right;margin:auto}.post-header{border-bottom:1px solid #333;margin:0 0 50px;padding:0}.post-title{font-size:55px;font-weight:900;margin:15px 0}.blog-description{color:#aeadad;font-size:14px;font-weight:600;line-height:1;margin:25px 0 0;text-align:center}.single-post-container{margin-top:50px;padding-left:15px;padding-right:15px;box-sizing:border-box}body.dark{background-color:#1e2227;color:#fff}body.dark pre{background:#282c34}body.dark table tbody>tr:nth-child(odd)>td,body.dark table tbody>tr:nth-child(odd)>th{background:#282c34}input{font-family:Inconsolata,monospace} body.dark .status.redirect{color:#ecdb54} body.dark input{border:1px solid ;border-radius: 3px; background:#282c34;color: white} body.dark label{color:#f1f0ea} body.dark pre{color:#fff}</style>
<script>
document.addEventListener('DOMContentLoaded', (event) => {
  ((localStorage.getItem('mode') || 'dark') === 'dark') ? document.querySelector('body').classList.add('dark') : document.querySelector('body').classList.remove('dark')
})
</script>" >> $outfile/$domain/$foldername/master_report.html
echo '<link rel="stylesheet" type="text/css" href="https://cdnjs.cloudflare.com/ajax/libs/material-design-lite/1.1.0/material.min.css">
<link rel="stylesheet" type="text/css" href="https://cdn.datatables.net/1.10.19/css/dataTables.material.min.css">
  <script type="text/javascript" src="https://code.jquery.com/jquery-3.3.1.js"></script>
<script type="text/javascript" charset="utf8" src="https://cdn.datatables.net/1.10.19/js/jquery.dataTables.js"></script><script type="text/javascript" charset="utf8" src="https://cdn.datatables.net/1.10.19/js/dataTables.material.min.js"></script>'>> $outfile/$domain/$foldername/master_report.html
echo '<script>$(document).ready( function () {
    $("#myTable").DataTable({
        "paging":   true,
        "ordering": true,
        "info":     false,
  "lengthMenu": [[10, 25, 50,100, -1], [10, 25, 50,100, "All"]],
    });
} );</script></head>'>> $outfile/$domain/$foldername/master_report.html



echo '<body class="dark"><header class="site-header">
<div class="site-title"><p>' >> $outfile/$domain/$foldername/master_report.html
echo "<a style=\"cursor: pointer\" onclick=\"localStorage.setItem('mode', (localStorage.getItem('mode') || 'dark') === 'dark' ? 'bright' : 'dark'); localStorage.getItem('mode') === 'dark' ? document.querySelector('body').classList.add('dark') : document.querySelector('body').classList.remove('dark')\" title=\"Switch to light or dark theme\">🌓 Light|dark mode</a>
</p>
</div>
</header>" >> $outfile/$domain/$foldername/master_report.html


echo '<div id="wrapper"><div id="container">' >> $outfile/$domain/$foldername/master_report.html
echo "<h1 class=\"post-title\" itemprop=\"name headline\">Recon Report for <a href=\"http://$domain\">$domain</a></h1>" >> $outfile/$domain/$foldername/master_report.html
echo "<p class=\"blog-description\">Generated by LazyRecon on $(date) </p>" >> $outfile/$domain/$foldername/master_report.html
echo '<div class="container single-post-container">
<article class="post-container-left" itemscope="" itemtype="http://schema.org/BlogPosting">
<header class="post-header">
</header>
<div class="post-content clearfix" itemprop="articleBody">
<h2>Total scanned subdomains</h2>
<table id="myTable" class="stripe">
<thead>
<tr>
 <th>Subdomains</th>
 <th>Scanned Urls</th>
 </tr>
 </thead>
<tbody>' >> $outfile/$domain/$foldername/master_report.html


cat $outfile/$domain/$foldername/urllist.txt |  sed 's/\http\:\/\///g' |  sed 's/\https\:\/\///g'  | while read nline; do
diresults=$(ls /opt/tools/dirsearch/reports/$nline/ | grep -v old)
echo "<tr>
 <td><a href='./reports/$nline.html'>$nline</a></td>
 <td>$(wc -l /opt/tools/dirsearch/reports/$nline/$diresults | awk '{print $1}')</td>
 </tr>" >> $outfile/$domain/$foldername/master_report.html
done
echo "</tbody></table>
<div><h2>Possible NS Takeovers</h2></div>
<pre>" >> $outfile/$domain/$foldername/master_report.html
cat $outfile/$domain/$foldername/pos.txt >> $outfile/$domain/$foldername/master_report.html

echo "</pre><div><h2>Wayback data</h2></div>" >> $outfile/$domain/$foldername/master_report.html
echo "<table><tbody>" >> $outfile/$domain/$foldername/master_report.html
[ -s $outfile/$domain/$foldername/wayback-data/paramlist.txt ] && echo "<tr><td><a href='./wayback-data/paramlist.txt'>Params wordlist</a></td></tr>" >> $outfile/$domain/$foldername/master_report.html
[ -s $outfile/$domain/$foldername/wayback-data/jsurls.txt ] && echo "<tr><td><a href='./wayback-data/jsurls.txt'>Javscript files</a></td></tr>" >> $outfile/$domain/$foldername/master_report.html
[ -s $outfile/$domain/$foldername/wayback-data/phpurls.txt ] && echo "<tr><td><a href='./wayback-data/phpurls.txt'>PHP Urls</a></td></tr>" >> $outfile/$domain/$foldername/master_report.html
[ -s $outfile/$domain/$foldername/wayback-data/aspxurls.txt ] && echo "<tr><td><a href='./wayback-data/aspxurls.txt'>ASP Urls</a></td></tr>" >> $outfile/$domain/$foldername/master_report.html
echo "</tbody></table></div>" >> $outfile/$domain/$foldername/master_report.html

echo '</article><article class="post-container-right" itemscope="" itemtype="http://schema.org/BlogPosting">
<header class="post-header">
</header>
<div class="post-content clearfix" itemprop="articleBody">' >> $outfile/$domain/$foldername/master_report.html
echo "<h2><a href='./aqua_out/aquatone_report.html'>View Aquatone Report</a></h2>" >> $outfile/$domain/$foldername/master_report.html
#cat $outfile/$domain/$foldername/ipaddress.txt >> $outfile/$domain/$foldername/master_report.html
echo "<h2>Dig Info</h2>
<pre>
$(dig $domain)
</pre>" >> $outfile/$domain/$foldername/master_report.html
echo "<h2>Host Info</h2>
<pre>
$(host $domain)
</pre>" >> $outfile/$domain/$foldername/master_report.html

echo "<h2>NMAP Results</h2>
<pre>
$(nmap -sV -T3 -Pn -p- $domain |  grep -E 'open|filtered|closed')
</pre>
</div></article></div>
</div></div></body></html>" >> $outfile/$domain/$foldername/master_report.html


}

logo(){
  #can't have a bash script without a cool logo :D
  echo "${red}
 _     ____  ____ ___  _ ____  _____ ____  ____  _
/ \   /  _ \/_   \\\  \///  __\/  __//   _\/  _ \/ \  /|
| |   | / \| /   / \  / |  \/||  \  |  /  | / \|| |\ ||
| |_/\| |-||/   /_ / /  |    /|  /_ |  \__| \_/|| | \||
\____/\_/ \|\____//_/   \_/\_\\\____\\\____/\____/\_/  \\|
${reset}                                                      "
}
cleandirsearch(){
  cat $outfile/$domain/$foldername/urllist.txt | sed 's/\http\:\/\///g' |  sed 's/\https\:\/\///g' | sort -u | while read line; do
  [ -d /opt/tools/dirsearch/reports/$line/ ] && ls /opt/tools/dirsearch/reports/$line/ | grep -v old | while read i; do
  mv /opt/tools/dirsearch/reports/$line/$i /opt/tools/dirsearch/reports/$line/$i.old
  done
  done
  }
cleantemp(){

    rm $outfile/$domain/$foldername/temp.txt
    rm $outfile/$domain/$foldername/tmp.txt
    rm $outfile/$domain/$foldername/domaintemp.txt
    rm $outfile/$domain/$foldername/cleantemp.txt

}
main(){
if [ -z "${domain}" ]; then
domain=${subreport[1]}
foldername=${subreport[2]}
subd=${subreport[3]}
report $domain $subdomain $foldername $subd; exit 1;
fi
  clear
  logo
  if [ -d "$outfile/$domain" ]
  then
    echo "This is a known target."
  else
    mkdir $outfile/$domain
  fi

  mkdir $outfile/$domain/$foldername
  mkdir $outfile/$domain/$foldername/aqua_out
  mkdir $outfile/$domain/$foldername/aqua_out/parsedjson
  mkdir $outfile/$domain/$foldername/reports/
  mkdir $outfile/$domain/$foldername/wayback-data/
  mkdir $outfile/$domain/$foldername/screenshots/
  touch $outfile/$domain/$foldername/crtsh.txt
  touch $outfile/$domain/$foldername/mass.txt
  touch $outfile/$domain/$foldername/cnames.txt
  touch $outfile/$domain/$foldername/pos.txt
  touch $outfile/$domain/$foldername/alldomains.txt
  touch $outfile/$domain/$foldername/temp.txt
  touch $outfile/$domain/$foldername/tmp.txt
  touch $outfile/$domain/$foldername/domaintemp.txt
  touch $outfile/$domain/$foldername/ipaddress.txt
  touch $outfile/$domain/$foldername/cleantemp.txt
  touch $outfile/$domain/$foldername/master_report.html

  cleantemp
  recon $domain
  master_report $domain
  echo "${green}Scan for $domain finished successfully${reset}"
  duration=$SECONDS
  echo "Scan completed in : $(($duration / 60)) minutes and $(($duration % 60)) seconds."
  cleantemp
  stty sane
  tput sgr0
}
todate=$(date +"%Y-%m-%d")
path=$(pwd)
foldername=recon-$todate
export GOROOT=/usr/local/go
export GOPATH=$HOME/go
export PATH=$GOPATH/bin:$GOROOT/bin:$PATH
main $domain
