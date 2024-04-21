require 'json'
require 'fileutils'
require './Utils'
require 'pathname'
require 'shellwords'

def readPrototypeKey(file, keyName)
  link = Shellwords.escape(file)
  %x{defaults read #{link} #{keyName}}.chomp
end

def parseAppInfo(appBaseLocate, appInfoFile)
  appInfo = {}
  appInfo['appBaseLocate'] = "#{appBaseLocate}"
  appInfo['CFBundleIdentifier'] = readPrototypeKey appInfoFile, 'CFBundleIdentifier'
  appInfo['CFBundleVersion'] = readPrototypeKey appInfoFile, 'CFBundleVersion'
  appInfo['CFBundleShortVersionString'] = readPrototypeKey appInfoFile, 'CFBundleShortVersionString'
  appInfo['CFBundleName'] = readPrototypeKey appInfoFile, 'CFBundleExecutable'
  appInfo
end

def scan_apps
  applist = []
  baseDir = '/Applications'
  lst = Dir.glob("#{baseDir}/*")
  lst.each do |app|
    appInfoFile = "#{app}/Contents/Info.plist"
    next unless File.exist?(appInfoFile)
    begin
      applist.push parseAppInfo app, appInfoFile
      # puts "Checking local App: #{appInfoFile}"
    rescue StandardError
      next
    end
  end
  applist
end

def checkCompatible(compatibleVersionCode, compatibleVersionSubCode, appVersionCode, appSubVersionCode)
  return true if compatibleVersionCode.nil? && compatibleVersionSubCode.nil?
  compatibleVersionCode&.each do |code|
    return true if appVersionCode == code
  end

  compatibleVersionSubCode&.each do |code|
    return true if appSubVersionCode == code
  end
  false
end

def main
  ret = %x{csrutil status}.chomp
  # System Integrity Protection status: disabled.
  if ret.include?("status: enabled")
    # puts "Turn off your SIP first! Is it illegal to turn off SIP?\nI've written that you should turn off SIP first. Can you read my instructions carefully?\nIf you've read them and still haven't turned it off, you're really a SB\nIf you haven't read the instructions, then you're more SB.\nWhatever, U ARE SB."
    # return
  end

  config = File.read("config.json")
  config = JSON.parse config
  basePublicConfig = config['basePublicConfig']
  appList = config['AppList']
  procVersion = config['Version']

  puts "====\tAutomatic Injection Started\t====\n"
  puts "====\tVersion: #{procVersion}\t====\n"
  puts "====\tAutomatic Inject Script Checking... ====\n"
  puts "====\tDesigned By QiuChenly(github.com/qiuchenly)"
  puts "When prompted, enter 'y' or press the Enter key to skip the current item.\n"

  install_apps = scan_apps

  # Prepare resolve package list
  appLst = []
  appList.each do |app|
    packageName = app['packageName']
    if packageName.is_a?(Array)
      packageName.each { |name|
        tmp = app.dup
        tmp['packageName'] = name
        appLst.push tmp
      }
    else
      appLst.push app
    end
  end

  appLst.each { |app|
    packageName = app['packageName']
    appBaseLocate = app['appBaseLocate']
    bridgeFile = app['bridgeFile']
    injectFile = app['injectFile']
    supportVersion = app['supportVersion']
    supportSubVersion = app['supportSubVersion']
    extraShell = app['extraShell']
    needCopy2AppDir = app['needCopyToAppDir']
    deepSignApp = app['deepSignApp']
    disableLibraryValidate = app['disableLibraryValidate']
    entitlements = app['entitlements']
    noSignTarget = app['noSignTarget']
    noDeep = app ['noDeep']

    localApp = install_apps.select { |_app| _app['CFBundleIdentifier'] == packageName }
    if localApp.empty? && (appBaseLocate.nil? || !Dir.exist?(appBaseLocate))
      next
    end

    if localApp.empty?
      puts "[🔔] This App package has an uncommon structure. Please note that the current App injection path is #{appBaseLocate}"
      # puts "Reading: #{appBaseLocate + "/Contents/Info.plist"}"
      localApp.push(parseAppInfo appBaseLocate, appBaseLocate + "/Contents/Info.plist")
    end

    localApp = localApp[0]
    if appBaseLocate.nil?
      appBaseLocate = localApp['appBaseLocate']
    end
    bridgeFile = basePublicConfig['bridgeFile'] if bridgeFile.nil?

    unless checkCompatible(supportVersion, supportSubVersion, localApp['CFBundleShortVersionString'], localApp['CFBundleVersion'])
      puts "[😅] [#{localApp['CFBundleName']}] - [#{localApp['CFBundleShortVersionString']}] - [#{localApp['CFBundleIdentifier']}] is not a supported version, skipping injection😋.\n"
      next
    end

    puts "[🤔] [#{localApp['CFBundleName']}] - [#{localApp['CFBundleShortVersionString']}] - [#{localApp['CFBundleIdentifier']}] is a supported version. Do you want to inject? y/n (default n)\n"
    action = gets.chomp
    next if action != 'y'
    puts "Start injecting App: #{packageName}"

    dest = appBaseLocate + bridgeFile + injectFile
    backup = dest + "_backup"

    if File.exist? backup
      puts "The backup file already exists. Do you want to use this file for injection? y/n (default y)\n"
      action = gets.chomp
      if action == 'n'
        FileUtils.remove(backup)
        FileUtils.copy(dest, backup)
      end
    else
      FileUtils.copy(dest, backup)
    end

    current = Pathname.new(File.dirname(__FILE__)).realpath
    current = Shellwords.escape(current)
    # Set shell +x permission
    sh = "chmod +x #{current}/tool/insert_dylib"
    system sh
    backup = Shellwords.escape(backup)
    dest = Shellwords.escape(dest)

    sh = "sudo #{current}/tool/insert_dylib #{current}/tool/libInjectLib.dylib #{backup} #{dest}"
    unless needCopy2AppDir.nil?
        system "sudo cp #{current}/tool/libInjectLib.dylib #{Shellwords.escape(appBaseLocate + bridgeFile)}libInjectLib.dylib"
        sh = "sudo #{current}/tool/insert_dylib #{Shellwords.escape(appBaseLocate + bridgeFile)}libInjectLib.dylib #{backup} #{dest}"
    end
    system sh

    signPrefix = "codesign -f -s - --timestamp=none --all-architectures"

    if noDeep.nil?
      puts "Need Deep Sign."
      signPrefix = "#{signPrefix} --deep"
    end

    unless entitlements.nil?
      signPrefix = "#{signPrefix} --entitlements #{current}/tool/#{entitlements}"
    end

    # Sign target file. If --deep is added, it will sign the entire app.
    if noSignTarget.nil?
      puts "Start signing..."
      system "#{signPrefix} #{dest}"
    end

    unless disableLibraryValidate.nil?
      sh = "sudo defaults write /Library/Preferences/com.apple.security.libraryvalidation.plist DisableLibraryValidation -bool true"
      system sh
    end

    unless extraShell.nil?
      system "sudo sh #{current}/tool/" + extraShell
    end

    if deepSignApp
       system "#{signPrefix} #{Shellwords.escape(appBaseLocate)}"
    end

    puts "App processing completed."
  }
end

main