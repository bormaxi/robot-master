#!/usr/bin/env ruby
# encoding: utf-8

require 'eventmachine'
require 'yaml'
require 'uri'
require "em_mysql2_connection_pool"
require "mysql2"
require 'em-http'
require 'date'
require "net/http"
require "uri"
require 'net/smtp'


$debug = true

$logged_in = false
$env = 'development'
config_rails = YAML.load_file('config/database.yml')
config = YAML.load_file('config/database.yml')
sqlconf = {
  :host => "localhost",
  :database => config[$env]['database'],
  :reconnect => true,  # make sure you have correct credentials
  :username => config[$env]['username'],
  :password => config[$env]['password'],
  :size => 30,
  :reconnect => true,
  :connections => 50
}

$sql_rails = Mysql2::Client.new(sqlconf)

$settings = $sql_rails.query("SELECT * FROM bot_settings")
begin
  $settings = $settings.to_a[0]
rescue
  p "Please set up bot first"
  exit!
end
p $settings
drupal_addr = $settings['drupal_path']

drupal_addr =  drupal_addr + "/" if drupal_addr[-1,1] != "/"

config_str = File.read(drupal_addr + "sites/default/settings.php")
config = config_str.scan(/(?:\$db_url.{0,100}:\/\/)([^:;]*?)(?::)([^@;]*?)(?:@)([^:;]*?)(?::\/)([^;']*?)(?:')/i)
config = config[config.size - 1]
p config
install_profile = config_str.scan(/(?:\$conf\[['"`]install_profile['"`]\].*?=.*?['"`])([^']*?)(?:['"`])/mi)
install_profile = install_profile[install_profile.size - 1][0]
p install_profile



sqlconf = {
  :host => config[2],
  :database => config[3],
  :reconnect => true,  # make sure you have correct credentials
  :username => config[0],
  :password => config[1],
  :size => 30,
  :reconnect => true,
  :connections => 50
}

$sql = EmMysql2ConnectionPool.new(sqlconf)
$sqlsync = Mysql2::Client.new(sqlconf)
$global_cookies = ""
$customcookie = ""
class Downloader  #class to brake protection
  include EM::Deferrable
  def initialize(url, postvar = Array.new, deep = 0,global_cookies = "", original = "")  #last two to veryfy proxy
    sleep(1)
    return false if url == nil
    return false if url.length < 15

    $global_cookies = global_cookies if global_cookies.length > 5

    #  p "downliading: #{url} "

    url = fix_link(url) if original == ""
    original = url if original == ""

    url =url.gsub(/:80|:433/,"")


    newlocation = url #to compare with new URL

    connection_opts = {
      :connect_timeout => 10,        # default connection setup timeout
      :inactivity_timeout => 120,
      :redirects => 3,
      :keepalive => true#,
      #:head => {"accept-encoding" => "gzip, compressed"}
    }


    $global_cookies = $customcookie if $global_cookies.length < 5
    $global_cookies = $customcookie if $global_cookies == nil
    newlocation = url #to compare with new URL
    oldcookie = $global_cookies
    p "cookie is" if $debug
    p $global_cookies if $debug
    #p "Connectinon opts"
    p connection_opts if $debug
    p url if $debug
    if postvar.length == 0
      p "issuing get request"
      @https = EM::HttpRequest.new(url,connection_opts).get :head => { "cookie" => $global_cookies, "user-agent" => "Mozilla/5.0 (Windows NT 6.1; WOW64) AppleWebKit/537.11 (KHTML, like Gecko) Chrome/23.0.1271.95 Safari/537.11"} #   #sendingrequest with our$global_cookiess
    else
      p "issuing post request"
      p postvar
      @https = EM::HttpRequest.new(url,connection_opts).post  :body => postvar , :head => { "cookie" => $global_cookies, "user-agent" => "Mozilla/5.0 (Windows NT 6.1; WOW64) AppleWebKit/537.11 (KHTML, like Gecko) Chrome/23.0.1271.95 Safari/537.11"} #   #sendingrequest with our$global_cookiess
    end


    @https.errback { |errors|
      p "err receive" if $debug
      p url  if $debug if $debug
      p errors.response if $debug
      p connection_opts if $debug

      @new_request = Downloader.new(fix_link(original), Array.new,deep + 1,"",original)
      @new_request.callback{|text|

        self.succeed(text)
      }

    }
    @https.callback {|http|
      begin
        html = ""
        html += http.response #to include set$global_cookies variables to verification process
        html = fix_downloader_text(html)
        validated =  validate_html(html)
        if validated == true
          p "VALIDATED!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!" if $debug
        end
        p "success receive!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!" if $debug

        if http != nil
          if http.response_header#.status/10).floor * 10 == 300 #support ofall 30* redirect codes
            newlocation = http.response_header['LOCATION'].gsub(":80","") # if 30* found -follow the link in headers
            #  p "new location is:"
            #  p newlocation
          end
        end
      rescue
      end

      $global_cookies = form_cookie(http.response_header['SET_COOKIE'],$global_cookies)
      p "new location is" if $debug
      p newlocation  if $debug

      p "url is" if $debug
      p url  if $debug

      p "original is" if $debug
      p original  if $debug
      redownload = false
      due = ""

      if newlocation.gsub(/:80|:433/,"") != url.gsub(/:80|:433/,"")
        redownload = true
        due += " URL (location) has been changed"
      end

      if http.response.length < 300
        redownload = true if oldcookie !=$global_cookies
        due += " cookies changed"
      end


      #  redownload = false if validated == true

      if redownload == true#if there were redirect



        p "REDOWNLOAD due to #{due} url:" if $debug
        p newlocation if $debug
        p "cookie:"
        p $global_cookies

        @new_request = Downloader.new(newlocation, Array.new,deep + 1,$global_cookies,original) #call itself
        @new_request.callback{|text|
          self.succeed(text)


        }


      else
        p "validation" if $debug

        #html = html.encode('UTF-8', :invalid => :replace,:undef => :replace)
        #html.encode!('UTF-8', 'UTF-8', :invalid => :replace,:undef => :replace)

        if validated
          html = $global_cookies + html
          p "passed" if $debug
          #$cache.set Digest::MD5.hexdigest(original) , 1 , 10 if html.index("Follow many redirects but still keep redirecting") == nil
          #p "downloaded"
          p original if $debug
          p "Receive succes with:"
          p connection_opts
          p html
          self.succeed(html)
        else
          @new_request = Downloader.new(fix_link(original), Array.new,deep+1,original)
          @new_request.callback{|text|

            self.succeed(text)
          }
        end
      end

    }


  end
end

def form_cookie(headers, cookies = "")
  cooks = Array.new

  if headers != nil
    p headers if $debug

    if headers.is_a?(String) #fix a littleinconstitance in eventmachine
      #p "cook is string"
      cooks[0] = headers #to have always an array
    else
      #p "cook is array"
      cooks = headers #because in case of onevalue of header em return string
    end
  end

  if cooks != nil

    cooks.each{|cook|

      begin
        cook_arr = /^(.*?)=(.*?);/mi.match(cook) #find keys and values inset_cookie header
        #  p "befor & after"
        #  p cookies
        if cookies.index(cook_arr[1] + "=") == nil
          if (cook_arr[2]+cook_arr[1]).index("=") == nil
            cookies += "&" if cookies.length != 0
            cookies += cook_arr[1] + "=" + cook_arr[2]  #and make it string
          end
        else
          cookies = cookies.gsub(/#{cook_arr[1]}=.*?($|&)/mi, "")
          cookies += "&" + cook_arr[1] + "=" + cook_arr[2]   #and make it string
        end
        #  p cookies
      rescue
      end
    }





  end

  return cookies
end

def fix_downloader_text(text)
  return text
end

def fix_link(text)
  return text
end
def validate_html(text)
  return true
end
def check_link(text)
  return true
end

def send_email(to,opts={})
  opts[:server]      ||= 'localhost'
  opts[:from]        ||= 'email@example.com'
  opts[:from_alias]  ||= opts[:from]
  opts[:subject]     ||= "You need to see this"
  opts[:body]        ||= "Important stuff!"

  msg = <<END_OF_MESSAGE
From: #{opts[:from_alias]} <#{opts[:from]}>
To: <#{to}>
Subject: #{opts[:subject]}
Content-Type: text/html; charset="utf-8"

<html>
    <head>
        <meta http-equiv="content-type" content="text/html; charset=utf-8" />
    </head>
    <body>
#{opts[:body]}
    </body>
END_OF_MESSAGE

  Net::SMTP.start(opts[:server]) do |smtp|
    smtp.send_message msg, opts[:from], to
  end
end

def process_reg_error(error, toreg)
  error = error.encode("utf-8")
  if $settings['double_reg_enabled'] == 1
    if error.index("Консультант с такими данными уже существует") != nil
      p "consultant already exists found"
      year_fix = $sql_rails.query("SELECT * FROM bot_checks_doubles WHERE was_registered = 0 AND  registration_id = #{toreg['id']}").to_a
      if year_fix != nil
        if year_fix[0] != nil
          if year_fix[0]['year_fix'] != nil
            $sql_rails.query("UPDATE bot_checks_doubles SET year_fix = year_fix + 1 WHERE registration_id = #{toreg['id']}")
            return false
          end
        end
      end

      passport = toreg["passportseries"] + " " + toreg["passportnumber"]
      #oblast = toreg["oblast"]
      rayon = toreg["district"]
      rayon = 'район' if rayon.length < 2
      city = toreg["tidvalue"]
      city = toreg["loctitle"] if city.length < 2
      ulitsa = toreg["street"]
      ulitsa = 'нет' if ulitsa.length < 2
      dom =  toreg["house"]
      dom += "-" + toreg["houseblock"] if toreg["houseblock"] .strip.length > 0
      flat = toreg["flat"] if toreg["flat"] .strip.length > 0

      bdate = DateTime.strptime(toreg['birthday'].to_s,'%s')
      year = bdate.strftime('%Y')
      month =  bdate.strftime('%m')
      day = bdate.strftime('%d')
      lastname = toreg["lastname"]
      firstname = toreg["firstname"] + " " + toreg["middlename"]
      index = toreg["pindex"]
      oblast = $sqlsync.query("SELECT * FROM ori_ru_state WHERE id = #{toreg['stid']}").to_a[0]['title'] #область из соседней таблицы

      text = $sql_rails.query("SELECT * FROM bot_templates WHERE bot_templates.for = 'double_message'").to_a[0]['template_text']



      data = "
      ФИО: #{firstname} #{lastname}<br>
      Дата рождения: #{day}/#{month}/#{year}<br>
      Паспорт (серия, номер): #{passport}<br>
      Адрес проживания<br>
      Индекс: #{index}<br>
      Страна: #{toreg["country"]}<br>
      Город: #{city}<br>
      Область: #{oblast}<br>
      Район: #{rayon}<br>
      Улица: #{ulitsa}<br>
      Дом: #{dom}<br>
      Квартира: #{flat}<br>
      "
      no = "http://" + $settings['server_ip'] + ":8000/?regok&id=" + toreg['id'].to_s
      yes = "http://" + $settings['server_ip'] + ":8000?regnotok&id=" + toreg['id'].to_s



      text = text.gsub("%data%", data)
      text = text.gsub("%no%", no)
      text = text.gsub("%yes%", yes)

      opts = Hash.new

      opts[:from]        = $settings['email_from']
      opts[:subject]     = 'Проверка регистрации консультанта'
      opts[:body]        = text

      send_email($settings['email_to'],opts)

      $sql.query("UPDATE  ori_user SET  status = 7, errortext = 'Консультант с такими данными уже существует. Отправлено сообщение в Ярославль' WHERE id = #{toreg['id']}") #ловим ошибку если не успешно
      $sql_rails.query("INSERT INTO bot_checks_doubles (registration_id, message_sent) VALUES (#{toreg['id']}, 'Sent on #{Time.now}')") #ловим ошибку если не успешно

    else
      $sql.query("UPDATE  ori_user SET  status = 7, errortext = '#{error}' WHERE id = #{toreg['id']}") #ловим ошибку если не успешно
    end
  else
    $sql.query("UPDATE  ori_user SET  status = 7, errortext = '#{error}' WHERE id = #{toreg['id']}") #ловим ошибку если не успешно
  end

end

def reg_user(toreg)
  email =  toreg["email"]  #берем все его данные ниже из таблицы для заполнения

  year_fix = $sql_rails.query("SELECT * FROM bot_checks_doubles WHERE was_registered = 0 AND registration_id = #{toreg['id']}").to_a
  if year_fix != nil

    if year_fix[0] != nil
      year_fix =   year_fix[0]['year_fix']
    else
      year_fix = 0
    end

  else
    year_fix = 0
  end
  tel = toreg["mccode"] + toreg["mprefix"] + toreg["mnumber"]
  passport = toreg["passportseries"] + " " + toreg["passportnumber"]
  #oblast = toreg["oblast"]
  rayon = toreg["district"]
  rayon = 'район' if rayon.length < 2
  city = toreg["tidvalue"]
  city = toreg["loctitle"] if city.length < 2
  ulitsa = toreg["street"]
  ulitsa = 'нет' if ulitsa.length < 2
  dom =  toreg["house"]
  dom += "-" + toreg["houseblock"] if toreg["houseblock"] .strip.length > 0
  dom += "-" + toreg["flat"] if toreg["flat"] .strip.length > 0

  bdate = DateTime.strptime(toreg['birthday'].to_s,'%s')
  year = bdate.strftime('%Y').to_i - year_fix
  year = year.to_s
  month =  bdate.strftime('%m')
  day = bdate.strftime('%d')
  lastname = toreg["lastname"]
  firstname = toreg["firstname"] + " " + toreg["middlename"]
  index = toreg["pindex"]
  pass = Random.rand(1111..9999)


  registration = Downloader.new("https://ru-eshop.oriflame.com/eShop/Consultant/OnlineQuickRegistration.aspx")  # эмулируем аякс запрос, будто бы вводим эти данные в поле формы
  registration.callback{|text2|
    begin
      oblast = $sqlsync.query("SELECT * FROM ori_ru_state WHERE id = #{toreg['stid']}").to_a[0]['title'] #область из соседней таблицы
      p oblast
      p text2
      if text2.index("Неавторизованный доступ</h1>") != nil
        $sql.query("UPDATE  ori_user SET  status = 7, errortext = 'Registration failed, unable to log in to oriflame by user\\'s sponsor ' WHERE id = #{toreg['id']}") #ловим ошибку если не успешно
      end

      if text2.index("ctl00_cphContent_pnlErrorPanel") != nil
        $sql.query("UPDATE  ori_user SET  status = 7, errortext = 'Registration failed, unable to log in to oriflame by user\\'s sponsor ' WHERE id = #{toreg['id']}") #ловим ошибку если не успешно
      end

      if text2.index("VIP registration is blocked.") != nil
        $sql.query("UPDATE  ori_user SET  status = 7, errortext = 'Registration failed, Сайт vip.oriflame.ru не доступен' WHERE id = #{toreg['id']}") #ловим ошибку если не успешно
      end
      ctl00_RadScriptManager1_TSM = URI.unescape(text2.match(/(?:_TSM_CombinedScripts_=)([^"]*?)(?:")/miu)[1].to_s) # подхватываем сессионные переменные с базы
      __EVENTVALIDATION = text2.match(/(?:id="__EVENTVALIDATION".{0,50}value=")([^"]*?)(?:")/im)[1]

      post = {  #и сам запрос
        "ctl00$RadScriptManager1" => "ctl00$cphContent$updPanel|ctl00$cphContent$cmbPostCode",
        "ctl00_RadScriptManager1_TSM" => ctl00_RadScriptManager1_TSM,
        "__EVENTTARGET" => "ctl00$cphContent$cmbPostCode",
        "__EVENTARGUMENT" => '{"Command":"TextChanged"}',
        "__LASTFOCUS" => "",
        "__VIEWSTATE" => "",
        "__EVENTVALIDATION" => __EVENTVALIDATION,
        "ctl00$cphContent$txtInputStep" => "0",
        "ctl00$cphContent$hidFBName" => "",
        "ctl00$cphContent$hidFB" => "",
        "ctl00$cphContent$txtEmail" => "",
        "ctl00$cphContent$txtPasswd" => pass,
        "ctl00$cphContent$txtLastName" => lastname,
        "ctl00$cphContent$txtFirstName" => firstname,
        "ctl00$cphContent$txtUniqueId" => passport,
        "ctl00$cphContent$dtpBirthDate" => "",
        "ctl00_cphContent_dtpBirthDate_dateInput_text" => "",
        "ctl00$cphContent$dtpBirthDate$dateInput" => "",
        "ctl00_cphContent_dtpBirthDate_dateInput_ClientState" => '{"enabled":true,"emptyMessage":"","minDateStr":"1/1/1900 0:0:0","maxDateStr":"'+month+'/'+day+'/'+year+' 0:0:0"}',
        "ctl00_cphContent_dtpBirthDate_calendar_SD" => "[]",
        "ctl00_cphContent_dtpBirthDate_calendar_AD" => "[[1900,1,1],[#{year},#{month},#{day}],[#{year},#{month},#{day}]]",
        "ctl00_cphContent_dtpBirthDate_ClientState" => '{"minDateStr":"1/1/1900 0:0:0","maxDateStr":"'+month+'/'+day+'/'+year+' 0:0:0"}',
        "ctl00$cphContent$cmbServiceCentre" => oblast,
        "ctl00_cphContent_cmbServiceCentre_ClientState" => '{"logEntries":[],"value":"","text":"'+oblast+'","enabled":true,"checkedIndices":[],"checkedItemsTextOverflows":false}',
        "ctl00$cphContent$cmbPostCode" => index,
        "ctl00_cphContent_cmbPostCode_ClientState" => '{"logEntries":[],"value":"","text":"'+index+'","enabled":true,"checkedIndices":[],"checkedItemsTextOverflows":false}',
        "ctl00$cphContent$cmbAddress3" => rayon,
        "ctl00_cphContent_cmbAddress3_ClientState" => '{"logEntries":[],"value":"","text":"'+rayon+'","enabled":true,"checkedIndices":[],"checkedItemsTextOverflows":false}',
        "ctl00$cphContent$cmbCity" => city,
        "ctl00_cphContent_cmbCity_ClientState" => '{"logEntries":[],"value":"","text":"'+city+'","enabled":true,"checkedIndices":[],"checkedItemsTextOverflows":false}',
        "ctl00$cphContent$cmbAddress1" => ulitsa,
        "ctl00_cphContent_cmbAddress1_ClientState" => '{"logEntries":[],"value":"","text":"'+ulitsa+'","enabled":true,"checkedIndices":[],"checkedItemsTextOverflows":false}',
        "ctl00$cphContent$txtAddress2" => "",
        "ctl00$cphContent$txtMobile" => "",
        "ctl00$cphContent$txtSponsorName" => "Надежда Геннадьевна Ахундова",
        "__ASYNCPOST" => "true"
      }

      save_postalcode = Downloader.new("https://ru-eshop.oriflame.com/eShop/Consultant/OnlineQuickRegistration.aspx",post) #тут уже будем формировать финальный запрос, будто бы нажали сохранить. После того как аякс запрос обработан сервером
      save_postalcode.callback{

        post = {
          "__VIEWSTATE" => "",
          "ctl00_cphContent_cmbServiceCentre_ClientState" => "",
          "ctl00_cphContent_cmbPostCode_ClientState" => "",
          "ctl00$cphContent$cmbAddress3" => "",
          "ctl00_cphContent_cmbAddress3_ClientState" => "",
          "ctl00_cphContent_cmbCity_ClientState" => "",
          "ctl00_cphContent_cmbAddress1_ClientState" => "",
          "__LASTFOCUS" => "",
          "__EVENTTARGET" => "",
          "__EVENTARGUMENT" => "",
          "__EVENTVALIDATION" => __EVENTVALIDATION,
          "ctl00$cphContent$txtInputStep" => "0",
          "ctl00_cphContent_dtpBirthDate_dateInput_text" => "#{day}.#{month}.#{year}",
          "ctl00$cphContent$txtAddress2" => dom,
          "ctl00$cphContent$txtPasswd" => pass,
          "ctl00$cphContent$cmbPostCode" => index,
          "ctl00$cphContent$dtpBirthDate" => "#{year}-#{month}-#{day}",
          "ctl00$cphContent$dtpBirthDate$dateInput" => "#{year}-#{month}-#{day}-00-00-00",
          "ctl00$cphContent$txtUniqueId" => passport,
          "ctl00$cphContent$txtMobile" => tel,
          "ctl00_RadScriptManager1_TSM" => ctl00_RadScriptManager1_TSM,
          "ctl00$cphContent$chkWithoutEmail" => "on",
          "ctl00$cphContent$chkAgreement" => "on",
          "ctl00$cphContent$chkAgreement2" => "on",
          "ctl00_cphContent_dtpBirthDate_calendar_AD" => "[[1900,1,1],[#{year},#{month},#{day}],[#{year},#{month},#{day}]]",
          "ctl00_cphContent_dtpBirthDate_calendar_SD" => "[[#{year},#{month},#{day}]]",
          "ctl00_cphContent_dtpBirthDate_dateInput_ClientState" => '{"enabled":true,"emptyMessage":"","minDateStr":"1/1/1900 0:0:0","maxDateStr":"'+month+'/'+day+'/'+year+' 0:0:0"}',
          "ctl00_cphContent_dtpBirthDate_ClientState" => '{"minDateStr":"1/1/1900 0:0:0","maxDateStr":"'+month+'/'+day+'/'+year+' 0:0:0"}',
          "ctl00$cphContent$btnNext" => "Зарегистрировать",
          "ctl00$cphContent$txtFirstName" => firstname,
          "ctl00$cphContent$txtLastName" => lastname,
          "ctl00$cphContent$cmbCity" => city,
          "ctl00$cphContent$cmbAddress1" => city,
          "ctl00$cphContent$cmbServiceCentre" => oblast,
          "ctl00$cphContent$txtSponsorName" => "Надежда Геннадьевна Ахундова"
        }

        registration2 = Downloader.new("https://ru-eshop.oriflame.com/eShop/Consultant/OnlineQuickRegistration.aspx",post) #сама фактически регистрация
        registration2.callback{|reg|
          p reg #в логи чтоб записалось то что вывелось для быстрого дебага
          begin
            begin
              password = reg.match(/(?:Password">)([^<]*?)(?:<\/span)/mi)[1] #берем логин и пароль из страницы, что нам показали
              number = reg.match(/(?:DistributorNumber">)([^<]*?)(?:<\/span)/mi)[1]
              $sql.query("UPDATE ori_user SET oriflamepassword = '#{password}', regnumber = '#{number}' , status = 5 WHERE id = #{toreg['id']}") #обновляем если все успешно
            rescue
              error = reg.match(/(?:errorResult.{0,1000}?<li>)(.{0,2000}?)(?:<\/li>)/mi)
              if error != nil #if error code is found
                p "error found"
                error = error[1]

                p error
                error.gsub!(/<.*?>/mi,"") #filter tags

                error = $sqlsync.escape(error)
                process_reg_error(error,toreg)
              else
                error = 'Registration failed because of unspecified reason - everything went OK but on final stage it was unable to find nor login/password nor error'
                $sql.query("UPDATE  ori_user SET  status = 7, errortext = '#{error}' WHERE id = #{toreg['id']}") #ловим ошибку если не успешно
              end

            end

          rescue Exception => e
            p e
            p e.backtrace
            $sql.query("UPDATE  ori_user SET  status = 7, errortext = 'Registration failed because of unspecified reason' WHERE id = #{toreg['id']}") #ловим ошибку если не успешно
          end
        }
      }
    rescue Exception => e

      p e
      p e.backtrace

      p "Unable to register, may be not logged in, trying to login"
    end
  }
end

def log_in(username, password, after, object, tries = 0)
  if tries > 2
    $sql.query("UPDATE ori_user SET  status = 7 , errortext = 'сайт випорифлейм перегружен - я отдыхаю включите меня через несколько часов. Ваш робот вердер.' WHERE id = #{object['id']}")
    if after == "changeemail"
      EM.stop
    else
      return false
    end
  end

  p "Trying to log in with username: '#{username}' and password: '#{password}'"
  prelogin = Downloader.new("https://ru-eshop.oriflame.com/eShop/Login.aspx")

  prelogin.callback{|text|
    begin
      ctl00_RadScriptManager1_TSM = URI.unescape(text.match(/(?:_TSM_CombinedScripts_=)([^"]*?)(?:")/miu)[1].to_s)
      __EVENTVALIDATION = text.match(/(?:id="__EVENTVALIDATION".{0,50}value=")([^"]*?)(?:")/miu)[1]
      post = {:ctl00_RadScriptManager1_TSM => ctl00_RadScriptManager1_TSM,  :__EVENTTARGET => "",
        :__EVENTARGUMENT => "", :__VIEWSTATE => "", :__EVENTVALIDATION => __EVENTVALIDATION,
        "ctl00$cphContent$txtUser" => username,
        "ctl00$cphContent$password" => password,
        "ctl00$cphContent$btnLogin" => "Войти"

      }


      login = Downloader.new("https://ru-eshop.oriflame.com/eShop/Login.aspx",post)

      login.callback{|text1|
        begin
          if text1.index("ctl00_cphContent_pnlErrorPanel") != nil
            $sql.query("UPDATE  ori_user SET  status = 7, errortext = 'Registration failed, unable to log in to oriflame by user\\'s sponsor ' WHERE id = #{object['id']}") #ловим ошибку если не успешно
          else


            $logged_in = true
            reg_user(object) if after == "register"

            if after == "changeemail"
              toreg = object

              number = toreg['regnumber']
              password = toreg['oriflamepassword']
              tel = toreg["mccode"] + toreg["mprefix"] + toreg["mnumber"]
              email =  toreg["email"]
              bdate = DateTime.strptime(toreg['birthday'].to_s,'%s')
              year = bdate.strftime('%Y')
              month =  bdate.strftime('%m')
              day = bdate.strftime('%d')
              p number
              p password
              change_email(number,password,email, tel,year,month,day,toreg)  #меняем емейл

            end
          end
        rescue Exception => e
          p e
          p e.backtrace
          $global_cookies = ""
          log_in(username, password, after, object, tries + 1)
        end
      }
    rescue Exception => e
      p e
      p e.backtrace
      $global_cookies = ""
      log_in(username, password, after, object, tries + 1)
    end

  }
end

def change_email(username,password,email, tel, byear, bmonth, bday, toreg) #ф-ция смены емейла. телефон и др для того чтоб не сканить страницу - т.к. форма отправляется не только с емейлом но со всеми данными кучей. Так не только проще но и надежнее

  mydata = Downloader.new("https://ru-eshop.oriflame.com/eShop/Consultant/Profile.aspx")
  mydata.callback{|html|
    ctl00_RadScriptManager1_TSM = URI.unescape(html.match(/(?:_TSM_CombinedScripts_=)([^"]*?)(?:")/miu)[1].to_s)
    __EVENTVALIDATION = html.match(/(?:id="__EVENTVALIDATION".{0,50}value=")([^"]*?)(?:")/im)[1]
    post = {
      "ctl00_RadScriptManager1_TSM" => ctl00_RadScriptManager1_TSM,
      "__EVENTTARGET" => "",
      "__EVENTARGUMENT" => "",
      "__VIEWSTATE" => "",
      "__EVENTVALIDATION" => __EVENTVALIDATION,
      "ctl00_cphContent_ProfileTabs_ClientState" => '{"selectedIndexes":["0"],"logEntries":[],"scrollState":{}}',
      "ctl00$cphContent$cmbGreeting" => "",
      "ctl00_cphContent_cmbGreeting_ClientState" => "",
      "ctl00$cphContent$dtpBirthDate" => "#{byear}-#{bmonth}-#{bday}",
      "ctl00_cphContent_dtpBirthDate_dateInput_text" => "#{bday}.#{bmonth}.#{byear}",
      "ctl00$cphContent$dtpBirthDate$dateInput" => "#{byear}-#{bmonth}-#{bday}-00-00-00",
      "ctl00_cphContent_dtpBirthDate_dateInput_ClientState" => '{"enabled":true,"emptyMessage":"","minDateStr":"1/1/1900 0:0:0","maxDateStr":"12/31/2099 0:0:0"}',
      "ctl00_cphContent_dtpBirthDate_calendar_SD" => "[]",
      "ctl00_cphContent_dtpBirthDate_calendar_AD" => "[[1900,1,1],[2099,12,30],[2013,3,20]]",
      "ctl00_cphContent_dtpBirthDate_ClientState" => '{"minDateStr":"1/1/1900 0:0:0","maxDateStr":"12/31/2099 0:0:0"}',
      "ctl00$cphContent$txtEmail" => email,
      "ctl00$cphContent$txtFBName" => "",
      "ctl00$cphContent$txtFB" => "",
      "ctl00$cphContent$cmbTelType" => "Mobile",
      "ctl00_cphContent_cmbTelType_ClientState" => "",
      "ctl00$cphContent$txtTelNumber" => tel,
      "ctl00$cphContent$txtOldPassword" => "",
      "ctl00$cphContent$txtNewPassword1" => "",
      "ctl00$cphContent$txtNewPassword2" => "",
      "ctl00$cphContent$grdAddr$ColumnWidths" => "",
      "ctl00_cphContent_grdAddr_ClientState" => "",
      "ctl00$cphContent$grdTel$ColumnWidths" => "",
      "ctl00_cphContent_grdTel_ClientState" => "",
      "ctl00$cphContent$txtPresentation" => "",
      "ctl00$cphContent$txt_SOCIAL_MEDIA_FACEBOOK" => "",
      "ctl00$cphContent$txt_SOCIAL_MEDIA_TWITTER" => "",
      "ctl00$cphContent$txt_SOCIAL_MEDIA_BLOG" => "",
      "ctl00_cphContent_ProfilePages_ClientState" => "",
      "ctl00$cphContent$btnSave" => "Сохранить"
    }
    changedata = Downloader.new("https://ru-eshop.oriflame.com/eShop/Consultant/Profile.aspx",post)
    changedata.callback{|chdata|
      p chdata
      if chdata.index(toreg['email']) != nil
        $sql.query("UPDATE ori_user SET  status = 6 WHERE id = #{toreg['id']}")
      else
        $sql.query("UPDATE ori_user SET  errortext = 'Change email FAILED!!!!' WHERE id = #{toreg['id']}")
      end
      EM.stop
    }

  }

end

module CheckerHandler
  def post_init
    @data_received = ""
    @line_count = 0
  end
  def receive_data data
    begin
      allok = true
      @data_received << data

      if @data_received.index("?regok")
        id = @data_received.match(/(?:id=)([0-9]*)/mi)[1]

        $sql_rails.query("UPDATE bot_checks_doubles SET replied = 1, was_registered = 0, year_fix = 1 WHERE registration_id = #{id}")

        thanks = $sql_rails.query("SELECT * FROM bot_templates WHERE bot_templates.for = 'thanks_double'").to_a[0]['template_text']
        send_data "HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nServer: Dvporg\r\nContent-type: text/html\r\n\r\n" + thanks
        $sql.query("UPDATE ori_user SET status = 2, errortext = '' WHERE id = #{id}")
        #SELECT * FROM ori_user WHERE status = 2 AND badindex = 0 LIMIT 1"
      elsif @data_received.index("?regnotok")
        id = @data_received.match(/(?:id=)([0-9]*)/mi)[1]
        $sql_rails.query("UPDATE bot_checks_doubles SET replied = 1, was_registered = 1 WHERE registration_id = #{id}")

        $sql.query("UPDATE ori_user SET status = 4, errortext = 'Консультант существует, проверено оператором г. Ярославль' WHERE id = #{id}")


        thanks = $sql_rails.query("SELECT * FROM bot_templates WHERE bot_templates.for = 'thanks_double'").to_a[0]['template_text']

        send_data "HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nServer: Dvporg\r\nContent-type: text/html\r\n\r\n"
        send_data thanks

      else
        send_data "HTTP/1.1 200 OK\r\nServer: Dvporg\r\nContent-type: text/html\r\n\r\n"

        if allok == false
          send_data "ERROR!!!!!!\r\n<br>"
        else
          send_data "OK"
        end


      end
      close_connection_after_writing
    rescue Exception => e
      p e
      p e.backtrace
    end
  end
end


def send_sms(to,text)

  uri = URI.parse("http://lcab.pravda-zdorovo.ru/API/XML/send.php")

  post_body = "<?xml version='1.0' encoding='UTF-8'?>
  <data>
  <login>oriflameda</login>
  <password>z5GqipfsxR9p</password>
  <action>send</action>
  <text>#{text}</text>
  <to number='#{to}'>#{to}</to>
  </data>"

  p post_body

  http = Net::HTTP.new(uri.host, uri.port)
  request = Net::HTTP::Post.new(uri.request_uri)
  request.body = post_body
  req = http.request(request)

  return req.body

end


EM.run{
  EventMachine::start_server "0.0.0.0", 8000, CheckerHandler  #чтоб робот просто откликался по порту, проверять запщен ли он. В хендлере возможно сделать какую-нить проверку, только вроде пока не на что проверять

  EM.add_periodic_timer(5){  #ищем аккаунты, где надо отправить СМС
    if $settings['sms_enabled'] == 1
      $sql.query("SELECT * FROM ori_user WHERE status = 8 LIMIT 1").callback{|obj|
        if obj.to_a.length > 0
          tosend = obj.to_a[0]
          tel = tosend["mccode"] + tosend["mprefix"] + tosend["mnumber"]
          email =  tosend["email"]
          text = "Регистрационные данные Oriflame и инструкция высланы на ваш e-mail #{email} !"
          response =  send_sms(tel,text)
          p response
          if response.index("<code>1</code>") != nil
            $sql.query("UPDATE ori_user SET  status = 9 WHERE id = #{tosend['id']}")
          else
            due = ""
            due = "due to WRONG PHONE NUMBER" if response.index("<code>510</code>") != nil

            $sql.query("UPDATE ori_user SET  status = 7 , errortext = 'Send SMS failed #{due}! On stage instruction sent ' WHERE id = #{tosend['id']}")
          end
        end
      }
    end
  }

  EM.add_periodic_timer(30){  #ищем аккаунты, где надо сменить емейлы
    $sql.query("SELECT * FROM ori_user WHERE status = 5 AND badindex = 0 LIMIT 1").callback{|obj|
      if obj.to_a.length != 0
        toreg = obj.to_a[0]

        EM.fork_reactor do
          $global_cookies = ""
          number = toreg['regnumber']
          password = toreg['oriflamepassword']
          log_in(number, password,"changeemail", toreg)
        end

      end
    }

  }

  $regtimer = EM.add_periodic_timer($settings['scan_time']){  #ищем конфирмд аккаунты с нормальным индексом
    if $settings['enabled'] == 1
      $sql.query("SELECT * FROM ori_user WHERE status = 2 AND badindex = 0 LIMIT 1").callback{|obj|
        if obj.to_a.length != 0

          toreg = obj.to_a[0]

          sponsor = $sqlsync.query("SELECT * FROM ori_user WHERE uid = #{toreg['psid']}").to_a[0]  #берем данные спонсора




          log_in(sponsor['regnumber'], sponsor['oriflamepassword'], "register", toreg) #логинимся на сайт орифлейма спонсором

        end
      }
    end
  }
  EM.add_periodic_timer(15){
    $settings = $sql_rails.query("SELECT * FROM bot_settings")
    begin
      $settings = $settings.to_a[0]
    rescue
      p "Please set up bot first"
      exit!
    end
    $regtimer.interval = $settings['scan_time']
  }

}

