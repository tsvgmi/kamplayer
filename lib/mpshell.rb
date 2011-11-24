#!/usr/bin/env ruby
#---------------------------------------------------------------------------
# File:        webpass.rb
# Date:        Wed Nov 07 09:23:03 PST 2007
# $Id: mpshell.rb 59 2010-08-17 23:52:43Z tvuong $
#---------------------------------------------------------------------------
#+++
require File.dirname(__FILE__) + "/../../etc/toolenv"
require 'fileutils'
require 'mtool/core'
require 'mtool/rename'
require 'yaml'

class CurrentSong
  attr_reader :info

  # Find by path: locate record, save it to file
  # Sync front end: load if change, locate record

  def initialize(playlist)
    @playlist = playlist
    refresh
  end

  def set_play_file(path)
    Plog.info("Set playfile to #{path}")
    fpath = @playlist.set_curplay(path)
    @info = Song.find(:first, :conditions=>"path like '#{fpath}%'")
  end

  def position
    @playlist.dbrec.curplay
  end

  def position=(value)
    Plog.info "Set curplay to #{value}"
    @playlist.dbrec.curplay = value
    @playlist.dbrec.save_wait
    refresh
  end

  def refresh
    @playlist.refresh
    curplay = @playlist.dbrec.curplay || 0
    if curplay >= @playlist.dbrec.pl_songs.size
      curplay = 0
    end
    begin
      @info = @playlist.dbrec.songs[curplay]
    rescue => errmsg
      p errmsg
      @info = Song.new
    end
  end

  def change(options)
    @info.change_rec(options)
  end

  def incr_playcount
    if @info
      @info.playcount += 1
      @info.lastplayed = Time.now
      @info.save_wait
    end
  end

  def set_duration(duration)
    if @info
      duration = duration.to_i
      if @info.duration != duration
        @info.duration = duration
        p @info
        @info.save_wait
      end
    end
  end

  def method_missing(symbol, *args)
    if @info
      @info.send(symbol, *args)
    else
      raise "No method: #{symbol}"
    end
  end
end

class PlayListCore
  attr_reader :data, :dbrec, :name

  def initialize(name)
    @name = name
    if (rec = PlayList.find(:first, :conditions=>["name=?", name])) == nil
      rec = PlayList.new(:name=>name)
      rec.save_wait
    end
    @dbrec = rec
    refresh
  end

  def concat(yrecs)
    rec = PlSong.find(:first, :select=>"max(play_order)+1 as mporder",
        :conditions=>["play_list_id=?", @dbrec.id])
    if rec
      order = rec.mporder.to_i
    else
      order = 0
    end
    yrecs.each do |yrec|
      @dbrec.pl_songs.create(:play_list_id=>@dbrec.id, :song_id=>yrec.id,
                             :play_order=>order)
      order += 1
    end
  end

  def reset
    @dbrec.pl_songs.clear
    @data = []
  end

  def refresh
    @dbrec = PlayList.find(:first, :conditions=>["name=?", @name],
                :include=>[:songs])
    @data  = @dbrec.songs
  end

  def [](index)
    @data[index]
  end

  def add_songs(mset, is_sort = false)
    mset = if is_sort
      mset.sort_by {|f| f.song + "-" + f.artist}
    else
      mset.sort_by {rand}
    end
    self.concat(mset)
    refresh
    mset
  end

  def gen_m3u(outfile = nil)
    outfile ||= "#{@name}.m3u"
    if @data.size <= 0
      Plog.error "No matching song found"
      return nil
    end
    Song.gen_m3u(outfile, @data)
    outfile
  end

  def fmt_text(aset = nil, pos = 0, curpos = -1, limit = 300)
    if aset
      has_state = false
    else
      aset = @data
      has_state = true
    end
    if aset.size <= 0
      return
    end
    if pos >= aset.size
      pos = aset.size - 1
    end
    pl_songs = has_state ? @dbrec.pl_songs : nil
    puts "Playlist: #{@name} [#{@data.size}]"
    @fmt_type = 1
    case @fmt_type
    when 1
      afmt = "%3d. %s [%d/%3d] %s %s %s %-12.12s: %s - %s"
    else
      afmt = "%3d. %-20.20s - [%1s] %s %s"
    end
    aset[pos..-1].each do |rec|
      case @fmt_type
      when 1
        times = "%2d:%02d" % [rec.duration/60, rec.duration%60]
        prec = [rec.sid, rec.rate, rec.playcount,
                Time.at(rec.lastplayed||0).strftime("%D"),
                Time.at(rec.mtime).strftime("%D"),
                times, rec.artist, rec.song, rec.tag]
      else
        prec = [rec.artist, rec.rate, rec.sid, rec.song]
      end
      if curpos && (curpos == pos)
        fmt = "*#{afmt}"
      else
        if !pl_songs || (pl_songs[pos].state == 0)
          fmt = " #{afmt}"
        else
          fmt = "-#{afmt}"
        end
      end
      prec.unshift(pos)
      puts fmt % prec
      pos += 1
      limit -= 1
      if limit <= 0
        break
      end
    end
  end
  
  def truncate(maxsize)
    # Truncate in db first
    songs = @dbrec.pl_songs
    if songs.size > maxsize
      sofs  = songs.size - maxsize
      Plog.info "Removing #{sofs} records"
      begin
        0.upto(sofs-1).each do |i|
          srec = songs[0]
          songs.delete(srec)
          srec.destroy
        end
      rescue => errmsg
        p errmsg
      end
      refresh
    end
    sofs
  end

  def disable_song(pos)
    Plog.info("Disable #{pos}")
    pos = pos.to_i
    if (pos >= 0) && (pos < @data.size)
      @dbrec.pl_songs[pos].state = 1
      @dbrec.pl_songs[pos].save_wait
    else
      Plog.warn "Invalid position #{pos}"
    end
  end

  def set_curplay(path, do_retry=true)
    rindex = -1
    
    # Must search from the currently so song could appear at multiple location
    startofs = @dbrec.curplay || 0
    if (startofs > 0) && (startofs < @data.size)
      walkset = (startofs..@data.size-1).to_a + (0..startofs-1).to_a
    else
      walkset = (0..@data.size-1).to_a
    end
    p "Searching for #{path} from #{walkset.first} of #{@data.size}"
    bpath = File.basename(path)
    walkset.each do |index|
      entry = @data[index]
      #p entry.path
      # Bad - mplayer truncate the report file now ....
      if File.basename(entry.path).index(bpath)
        rindex = index
        break
      end
    end
    if (rindex >= 0) && (rindex <= @data.size)
      p "Set curplay to #{rindex}"
      @dbrec.curplay = rindex
      @dbrec.save_wait
    else
      p "Out of bound: startofs=#{startofs}, size=#{@data.size}, #{rindex} - ignore"
      refresh
      # Retry it once more
      if do_retry
        set_curplay(path, false)
      end
    end
    if @data[rindex]
      @data[rindex].path
    else
      ""
    end
  end

end


# Remote controller for Mplayer via its RC interface.  Use the input pipe
# to write command, and monitor output file for any status change.  Start
# method should be used here to setup the matching interface.
class MPlayerRC
  MINPUT     = "mp.input"
  MOUTPUT    = "mp.output"

  attr_reader :rchan, :wchan

  def initialize(options = {})
    @options = options
    @trace   = options[:trace]
    @wchan   = nil
    unless test(?f, MOUTPUT)
      File.open(MOUTPUT, "w") {}
    end
    @rchan = File.open(MOUTPUT)
    @rchan.seek(0, 2)
  end

  def send(acmd, wait = 0)
    if @trace
      Plog.info "Sending #{acmd}"
    end
    return if @options[:sim]
    unless @wchan
      @wchan = File.open(MINPUT, "w")
    end
    @wchan.puts("#{acmd}")
    @wchan.flush
    if wait > 0
      get_response(wait)
    end
  end

  def get_response(timeout)
    return if @options[:sim]
    while timeout > 0
      while line = @rchan.gets
        if @trace
          print line
        end
      end
      sleep 1
      timeout -= 1
    end
  end

  def monitor_start
    @rchan.seek(0, 2)
  end

  def monitor_for
    # Loop and wait till event is detected.
    lcnt   = 0
    scount = 0
    while true
      while line = @rchan.gets
        if yield(line, lcnt)
          return true
        end
        lcnt += 1
      end
      sleep 1
      scount += 1
      if scount >= 5
        send "get"
        scount = 0
      end
    end
    false
  end

  # Cannot start by object b/c object represent channel which cannot
  # be opened till the process have been started.
  def self.start(options)
    return if options[:sim]
    cache = options[:cache] || 8000
    MPlayer.kill_process(/mplayer.*-slave/)
    unless test(?p, MINPUT)
      Pf.system("mkfifo #{MINPUT}", 1)
    end
    #popt = "-autosync 30 -slave -quiet -framedrop -rootwin -vf yadif -nograbpointer -vf scale -idle -double"
    popt = "-autosync 30 -slave -quiet -framedrop -rootwin -nograbpointer -idle"
    if osd = options[:osd]
      popt += " -osdlevel #{osd}"
    end
    if options[:fs]
      popt += " -fs"
    else
      popt += " -geometry 0:0"
    end
    if screen = options[:screen]
      popt += " -xineramascreen #{screen}"
    end
    Pf.system("mplayer -idx -cache #{cache} #{popt} -input file=#{MINPUT} >>#{MOUTPUT} 2>&1 &", 1)
  end

  def self.setup
    File.open(MOUTPUT, "w") {}
  end
end

class MPlayer
  attr_accessor :trace, :pmode, :cursong, :scan_mode, :playlist, :rc

  def initialize(playlist, options)
    @wchan   = nil
    @rc      = MPlayerRC.new(options)
    @channel = :left
    @aspect  = :normal
    @pmode   = :sound
    @options = options
    @volume  = (options[:volume] || 50).to_i

    @cursong   = CurrentSong.new(playlist)
    @playlist  = playlist
    @scan_mode = false
    @listsize  = 20

    @pmode = @options[:karaoke] ? :karaoke : :sound
    @trace = @options[:verbose]
  end

# This is _run after player has started
  def run_init
    slist    = @playlist.data

    # Skip the ones already played.
    if (opos = @cursong.position) > 0
      if opos < slist.size
        @playlist.truncate(slist.size - opos)
        @cursong.position = 0
        slist = @playlist.data
      end
    end

    # This must run after the player has started
    if slist.size > 0
      add_songs(slist, true)
    end
    @cursong.refresh
  end

  # Start the stand-alone monitor
  def self.start_monitor
    stop_monitor
    sleep(2)
    opt = "-c -k"
    [:karaoke, :verbose].each do |anopt|
      if MPShell.getOption(anopt)
        opt += " --#{anopt}"
      end
    end
    Pf.system("#{__FILE__} #{opt} pmonitor &", 1)
  end

  def self.stop_monitor
    kill_process(/ruby.*pmonitor/)
  end

  def self.kill_process(ptn, sig = "HUP")
    Plog.warn "Stopping process #{ptn}"
    pids = `ps -ax`.grep(ptn).map do |aline|
      aline.split.first.to_i
    end
    if pids.size > 0
      Process.kill("HUP", *pids)
      sleep(1)
    end
    pids
  end

  def stop(killit = false)
    send "stop"
    MPlayer.kill_existing_players if killit
  end

  def toggle_pmode(newmode = nil)
    omode  = @pmode
    unless newmode
      @pmode = (@pmode == :sound) ? :karaoke : :sound
    else
      @pmode = newmode.intern
    end
    sound_normalize(nil, omode)
    self
  end

  def toggle_trace
    @trace = !@trace
    Plog.info "Trace is #{@trace}"
    self
  end

  def toggle_scan
    @scan_mode = !@scan_mode
    Plog.info "Scan mode is #{@scan_mode}"
  end

  def osd(msg)
    send("osd_show_text '#{msg}' 3000")
  end

  def send(msg, wait = 0)
    @rc.send(msg, wait)
  end

  def add_songs(mset, renew)
    Plog.info "Adding #{mset.size} song to player"
    ftime = true
    mset.each do |entry|
      file = entry[:path]
      if file =~ /'/
        Plog.warn "Cannot post file with ': #{file}"
        next
      end
      if renew
        send("loadfile '#{file}' 0", 3)
        renew = false
      else
        send("loadfile '#{file}' 1")
      end
      #---------------- 1st time must delay.  MP may be too busy startup ---
      if ftime
        sleep 2
        ftime = false
      end
    end
    sleep 2
    @playlist.fmt_text(mset)
  end

  def switch_audio(mode = "")
    send "pausing_keep_force switch_audio #{mode}"
    send 'seek -5 0'
  end

  def sound_normalize(ksel = nil, omode = nil)
    unless ksel
      @cursong.refresh
      ksel = (@cursong.ksel || "").sub(/^.*\./, '')
    end
    Plog.info "Switch to #{@pmode}"
    case ksel[0,1]
    when 'F'
      if @pmode == :sound
        switch_audio
      else
        if omode && (omode == :sound)
          switch_audio
        end
      end
    when 'S'
      if @pmode == :karaoke
        switch_audio 2
      else
        if omode && (omode == :karaoke)
          send switch_audio
        end
      end
    when 'L'
      if @pmode == :sound
        send "balance 2"
      else
        send "balance -2"
      end
    when 'R'
      if @pmode == :karaoke
        send 'balance 2'
      else
        send 'balance -2'
      end
    end

    case ksel[1,1]
    when 'W'
      send 'switch_ratio 1.6667'
    when 'N'
      send 'switch_ratio 1.3333'
    end

    send "volume #{@volume} 1"
    send "get_time_length", 1
  end

  def song_step(step)
    step  = step.to_i
    nstep = (step > 0) ? 1 : -1
    if step == 0
      send 'seek 1 2'
      return
    end

    # Need to skip over the disabled songs
    acstep  = 0
    plsongs = @playlist.dbrec.pl_songs
    curpos  = @cursong.position
    curpos += step
    acstep += step
    while (curpos >= 0) && (curpos < @playlist.data.size)
      if plsongs[curpos].state == 0
        break
      end
      Plog.info "Skipping #{curpos} - #{@playlist[curpos].song}"
      curpos += nstep
      acstep += nstep
    end
    if (curpos < 0) || (curpos >= @playlist.data.size)
      Plog.warn "Move to out of range #{curpos}"
      return
    end
    @cursong.position = curpos

    send("pausing_keep_force pt_step #{acstep}", 3)
    if @scan_mode
      sleep 3
      send "seek 60"
    end
  end

  def song_jump(target)
    @cursong.refresh
    if (cur_index = @cursong.position) >= 0
      offset = target - cur_index
      song_step(offset)
    end
  end
  
  def switch_channel
    if @channel == :left
      send "balance 2"
      @channel = :right
    else
      send "balance -2"
      @channel = :left
    end
    send "volume #{@volume} 1"
  end

  def switch_aspect
    if @aspect == :normal
      send "switch_ratio 1.667"
      @aspect = :wide
    else
      send "switch_ratio 1.333"
      @aspect = :normal
    end
  end
  
  def show_playlist(range = nil)
    if @playlist.data.size <= 0
      return
    end
    @cursong.refresh
    cur_index = @cursong.position
    if range
      start, size = range.split(/,/)
      start = start.empty? ? cur_index-3 : start.to_i
      if size
        @listsize = size.to_i
      end
    else
      start = cur_index - 3
      size = @listsize
    end
    start = 0 if (start < 0)
    size ||= @listsize
    @playlist.fmt_text(nil, start, cur_index, size.to_i)
  end

  # Monitor the file being played.  When mplayer switch to new song,
  # it will be detected here.
  def monitor_curfile
    file    = nil
    stopped = false
    @rc.monitor_for do |line, lcnt|
      case line
      when /^Playing\s+/
        file = $'.chomp.sub(/\.$/, '')
        unless file.empty?
          if @options[:verbose]
            Plog.info "Detect #{File.basename(file)}"
          end
          @lastfile = file
          return @lastfile
        end
      when /^Exiting\.\.\./
        Plog.warn "#{lcnt}. Mplayer exit ******"
      when /ANS_LENGTH=/
        duration = $'.sub(/\..*$/, '')
        #p "**** #{@lastfile}: #{duration}"
        @cursong.set_duration(duration)
      when /ANS_PERCENT_POSITION=/
        pcent = $'.strip.to_i
        if pcent >= 98
          sfiles = Dir.glob("/Users/thienvuong/kamplayer/webapp2/public/sound/*.wav")
          if (fcount = sfiles.size) > 0
            sfile = sfiles[rand(fcount)]
            system "afplay --volume 8 #{sfile} &"
          end
        end
      when /MPlayer interrupted by signal/
        Plog.warn $line
        stopped = true
      end
      false
    end
  end
end

class CmdLine
  def self.parse_range(*input)
    result = []
    input.map{|w| w.split(',')}.flatten.each do |aword|
      case aword
      when /-/
        rstart, rend = aword.split(/-/)
        result.concat((rstart.to_i..rend.to_i).to_a)
      else
        result << aword.to_i
      end
    end
    result
  end
end

class MPShell
  extendCli __FILE__

  MaxInitListSize = 3000
  ShellFifo       = "monrem.fifo"

  def initialize(options)
    @playlist = PlayListCore.new("mpshell")
    @options  = options.clone
    if @options[:keep]
      @playlist.truncate(MaxInitListSize)
    else
      @playlist.reset
    end
    @player    = MPlayer.new(@playlist, options)
    @matchset  = []
    @scan_mode = false
    @cursong   = @player.cursong
    @loadat    = Time.now
  end

  # Called from menu only
  def start(oper = nil)
    oper ||= ""
    oper.split.each do |assign|
      var, val = assign.split(/=/)
      @options[var.intern] = val
    end
    MPlayerRC.start(@options)
    sleep(3)
    @player.run_init
  end

  def song_info(*data)
    if data[0]
      dbrec    = Song.find_by_id(data[0].to_i)
      position = 0
    else
      dbrec    = @cursong.info
      position = @cursong.position
    end
    slist  = @playlist.data
    unless dbrec
      return
    end
    lastplayed = Time.at(dbrec.lastplayed || 0)
    stars  = "**********"[0,dbrec.rate.to_i]
    puts <<EOF
+======================================================================
| SID:    #{dbrec.sid} #{position}/#{slist.size-1} RT:#{stars} PC:#{dbrec.playcount} LP:#{lastplayed.strftime('%D')}
| Song:   #{dbrec.song} - #{dbrec.artist}
| Lyrics: #{dbrec.lyrics}
| Tag:    #{dbrec.tag}
| Cfile:  #{dbrec.cfile}
| PM:#{@player.pmode} TRC:#{@player.trace} PC:#{dbrec.playcount} LP:#{lastplayed.strftime('%D')}
+======================================================================
EOF
    unless data[0]
      msg = "#{dbrec.sid} #{dbrec.song} - #{dbrec.artist}"
      @player.osd(msg)
    end
  end

  def _rl_init
    require 'readline'

    cmdlist = [
      'stop'
    ]
    (self.public_methods - self.class.superclass.instance_methods).each do |amethod|
      if amethod =~ /^[a-z][a-z0-9_]*$/
        cmdlist << amethod
      end
    end
    cmdlist = cmdlist.sort
    comp = proc {|s| cmdlist.grep(/^#{s}/).map{|f| "#{f} "}}
    Readline.completion_append_character = ":"
    Readline.completion_proc = comp
  end

  # Main run loop.  Start with _ to hide from shell
  def _run
    MPlayerRC.start(@options)
    sleep(3)
    @player.run_init
    if @options[:readline]
      _rl_init
    end

    while true
      #@cursong.refresh
      if @options[:nomonitor]
        song_info
      end
      puts <<EOF
n(Next) p(Prev) f(ullscreen) h(help) v(oice) w(ide) quit
EOF
      if @options[:readline]
        input = Readline::readline("> ", true)
      else
        print "> "
        STDOUT.flush
        input = STDIN.gets
      end
      break unless input
      done = false
      input.strip.split(/;/).each do |acommand|
        cmd, oper = acommand.strip.sub(/^[-\+\/][\+]?/, '\& ').split(' ', 2)
        begin
          unless _run_a_line(cmd, oper)
            done = true
            break
          end
        rescue => errmsg
          p errmsg
          puts errmsg.backtrace
        end
      end
      break if done
      _reload
    end

    @playlist.truncate(MaxInitListSize)
    @player.stop
  end

  def _run_a_line(cmd, oper)
    case cmd
    when 'exit', 'stop', 'quit'
      return false
    when /^[0-9\.][0-9,]*$/
      if oper
        song_change(cmd, oper)
      else
        @player.song_jump(cmd.to_i)
      end
    when '/'
      search(oper)
    when /=/
      song_change('.', "#{cmd} #{oper}")
    else
      if cmd
        if (ncmd = Abbrev[cmd])
          cmd = ncmd
        end
        oper ||= ""
        if self.respond_to?(cmd)
          self.send(cmd, *oper.split)
        elsif self.class.respond_to?(cmd)
          self.class.send(cmd, *oper.split)
        else
          if cmd !~ /^q/
            Plog.info "Sending #{cmd} #{oper}"
            @player.send("#{cmd} #{oper}", 2)
          else
            Plog.info "Can't send q to player"
          end
        end
      end
    end
    true
  end

  # Temp macro for new file
  def qset(newrate, tag=nil)
    song_change(".", "rt=#{newrate}")
    if tag
      song_change(".", "tag=#{tag}")
    end
    next_song
    sleep(2)
    seek("60")
  end
  
  Abbrev = {
    '?'  => 'help',
    '+'  => 'add',
    '++' => 'listnew',
    '-'  => 'disable',
    'c'  => 'chan',
    'd'  => 'trace',
    'f'  => 'full',
    'h'  => 'help',
    'i'  => 'song_info',
    'k'  => 'pmode',
    'l'  => 'list',
    'n'  => 'next_song',
    'p'  => 'prev_song',
    'r'  => 'rewind',
    's'  => 'seek',
    't'  => 'track',
    'v'  => 'voice',
    'V'  => 'volume',
    'w'  => 'wide',
    'x'  => 'quit',
  }

  def help
    puts <<EOF
#:      Jump to track #
/spec:  Search for spec
+ ptn:  Add ptn to playlist
++ ptn: Reset playlist to ptn
c:      Toggle channel (left/right)
d:      Toggle debug mode
f:      Toggle fullscreen
i:      Show info
k:      Toggle karaoke mode
l:      Show playlist
n [#]:  Next or jump to track #
p:      Previous track
t:      Switch to next track
v:      Toggle voice (track or channel)
V:      Set volume
start:  start mplayer (if it quit)
stop:   stop mplayer (quit/exit)

# Change current rec
field=value[,field=value...]

# Change other rec
rec1[,rec2,...] field=value[,field=value,...]
EOF
  end

  def add(*list)
    mset = _search(list.join(' '), @matchset)
    if mset.size > 0
      mset = @playlist.add_songs(mset)
      @player.add_songs(mset, false)
    end
  end

  def listnew(*list)
    mset = _search(list.join(' '), @matchset)
    if mset.size > 0
      @playlist.reset
      mset = @playlist.add_songs(mset)
      @player.add_songs(mset, true)
    end
  end

  def list(ptn = nil)
    @cursong.refresh
    @player.show_playlist(ptn)
  end

  def playlist(*list)
    case list.size
    when 0
      PlayList.find(:all, :order=>'name').each do |rec|
        puts "%-20s: %3d" % [rec.name, rec.pl_songs.size]
      end
    # Specify a new playlist.  We need to restart the player
    when 1
      name = list[0]
      if name == '%pack'
        PlayList.find(:all, :order=>'name').each do |rec|
          puts "%-20s: %3d" % [rec.name, rec.pl_songs.size]
        end
        PlSong.delete_all(
          "play_list_id=#{@playlist.dbrec.id} and state!=0")
        name = @playlist.name
      end
      @playlist        = PlayListCore.new(name)
      @player.playlist = @playlist
      @cursong         = CurrentSong.new(@playlist)
      @player.run_init
    else
      Plog.error "Unknown input"
    end
  end

  def delfile(input)
    _records(input).each do |sid|
      if arec = Song.find_by_id(sid)
        begin
          FileUtils.remove(arec.path, :verbose=>true)
        rescue Errno::ENOENT
        end
        arec.state = 'N'
        arec.save_wait
      end
    end
    if @mpattern
      @matchset = Song.search(@mpattern)
    end
  end

  # sids: #,#,#,...
  # cmds: field=val,field=val,...
  def song_change(sids, cmds)
    cmdset = []
    cmds.split(/,/).each do |acmd|
      var, val = acmd.split(/\s*=\s*/)
      if val
        cmdset << [var.intern, val]
      else
        Plog.error "Change must use var=val"
      end
    end

    sids.split(/,/).each do |sid|
      if sid == '.'
        @cursong.refresh
        asong = @cursong.info
      else
        if (asong = Song.find_by_id(sid.to_i)) == nil
          Plog.error "Song #{sid} not found"
          next
        end
      end
      asong.change_rec(cmdset)
    end
  end

  def chan
    Plog.info "Switch channel"
    @player.switch_channel
  end

  def track
    Plog.info "Switch track"
    @player.switch_audio
    @player.send "volume #{@volume} 1"
  end

  def voice
    if @cursong.ksel !~ /[FS]/
      chan
    else
      track
    end
  end

  def debug
    @player.toggle_trace
  end

  def pmode(mode = nil)
    @player.toggle_pmode(mode)
  end

  def trace
    @player.trace = true
  end

  def scan
    @player.toggle_scan
  end

  def rewind
    @player.send "seek 1 2"
  end

  def seek(*data)
    @player.send "seek #{data.join(' ')}"
    #@player.send "seek #{data} 1"
  end

  def volume(data)
    case data
    when /^\d+$/
      @volume = data.to_i
    when /^\+/
      @volume += (10 * data.size)
    when /^\-/
      @volume -= (10 * data.size)
    else
      return
    end
    Plog.info "Setting volume level to #{@volume}"
    @player.send "volume #{@volume} 1"
  end

  def wide
    @player.switch_aspect
  end

  def full
    @player.send "vo_fullscreen"
  end

  def search(data)
    if data
      @mpattern = data
      @matchset = _search(@mpattern)
    end
    @playlist.fmt_text(@matchset)
  end

  def _search(ptn, matchset = [])
    mset = []
    if ptn =~ /^[0-9][-0-9,]*$/
      ptn.split(',').each do |anentry|
        number = anentry.to_i
        # Use local search set
        if (number < matchset.size)
          number = matchset[number].id
        end
        song = Song.find_by_id(number)
        if song
          mset << song
        else
          Plog.error "Cannot find song ##{number}"
        end
      end
    else
      mset.concat(Song.search(ptn))
    end
    mset
  end

  def _records(input)
    input.split(',').map do |anentry|
      number = anentry.to_i
      if (number < @matchset.size)
        number = @matchset[number].id
      end
      number
    end
  end

  # Test vector
  def ns(pos = nil)
    next_song(pos)
    seek(60)
  end

  def next_song(pos = nil, start_at = nil)
    if pos
      if pos =~ /^[-+]/
        @player.song_step(1)
      else
        @player.song_jump(pos.to_i)
      end
    else
      @player.song_step(1)
    end
    seek(start_at) if start_at
  end

  def prev_song
    @player.song_step(-1)
  end

  def disable(*ranges)
    CmdLine.parse_range(*ranges).each do |idx|
      @playlist.disable_song(idx)
    end
  end

  def _traceon
    set_trace_func proc {|event, file, line, tid, binding, classname|
      doprint = false
      case event
      when 'call', 'return'
        doprint = true
      end
      if doprint
        printf "%8s %12s:%03d %10s %8s\n", event, File.basename(file), line, tid, classname
      end
    }
  end

  def _reload(force = nil)
    fset = ["#{ENV['HOME']}/bin/mtool/rename.rb", __FILE__]
    if !force
      if @loadat
        fset.each do |ascript|
          if @loadat < File.mtime(ascript)
            force = true
            break
          end
        end
      else
        force = true
      end
    end

    if force
      begin
        fset.each do |ascript|
          load ascript
        end
        @loadat = Time.now
      rescue => errmsg
        p errmsg
      end
      true
    else
      false
    end
  end

  def _pmonitor(standalone = false)
    @player.rc.monitor_start
    ftime = false
    sample_time = @options[:sample]
    mthread = nil
    while true
      # Get the next file
      curfile = @player.monitor_curfile

      # Refresh the playlist - file changed.  This is to pickup any
      # changes from the foreground shell and sync it with this thread.
      if standalone
        @playlist.refresh
      end
      
      @cursong.set_play_file(curfile)
      @cursong.incr_playcount

      song_info
      if @options[:verbose]
        p @cursong.info
      end

      msg = "#{@cursong.sid} #{@cursong.song} - #{@cursong.artist}"
      sleep 3
      # Put up an OSD message on the player
      @player.osd(msg)

      # Switch track or channel based on play mode
      @player.sound_normalize(@cursong.ksel)
      Plog.info(msg)

      # Sample mode, we skip to next one after a sample time.
      if sample_time
        @player.send "seek 45 2"
        if mthread
          Plog.warn "Kill pending update thread ..."
          Thread.kill mthread
          mthread = nil
        end
        mthread = Thread.new {
          sleep sample_time.to_i
          @player.send("pausing_keep_force pt_step 1")
        }
      end
    end
  end

  def remote_command(cpipe = ShellFifo)
    unless test(?p, cpipe)
      Pf.system("mkfifo ./#{cpipe}")
    end
    fid = File.open(cpipe)
    while true
      while line = fid.gets
        cmd, oper = line.strip.sub(/^[-\+\/][\+]?/, '\& ').split(' ', 2)
        begin
          unless _run_a_line(cmd, oper)
            done = true
            break
          end
        rescue => errmsg
          p errmsg
          puts errmsg.backtrace
        end
      end
      sleep 1
    end
    fid.close
  end

  def _artists(*args)
    Song.find(:all, :select=>'*, count(*) as count',
        :group=>'artist', :order=>"artist",
        :conditions=>"state='Y'").each do |r|
      if r.count.to_i >= 10
        puts "%-30s %3s" % [r.artist, r.count]
      end
    end
  end

  # Run the playlist in VLC (for checking)
  def vlc(*args)
    if args.size > 0
      m3ufile = @playlist.gen_m3u
    else
      m3ufile = Song.gen_m3u(@cursong.artist, [@cursong.info])
    end
    Pf.system("open -a vlc '#{m3ufile}'", 1)
  end

  # Run the current song in MPlayer GUI - for checking
  def mplay(*args)
    Pf.system("open -a 'MPlayer OSX Extended' '#{@cursong.path}'")
  end

  # Run player monitor mode
  def self.pmonitor
    DbAccess.instance
    MPShell.new(getOption)._pmonitor(true)
  end

  def self.pmonitor2
    DbAccess.instance
    options        = getOption
    options[:keep] = true
    Thread.abort_on_exception = true
    ashell = MPShell.new(options)
    monthread = Thread.new {
      ashell._pmonitor(true)
    }
    cmdthread = Thread.new {
      ashell.remote_command
    }
    monthread.join
    cmdthread.join
  end

  def self.run
    DbAccess.instance
    MPlayerRC.setup

    # Override or preset config?
    cf_file = getOption(:config) || "#{ENV['HOME']}/.mpshellrc"
    if test(?f, cf_file)
      MPShell.setOptions(YAML.load(File.read(cf_file)))
    end

    ashell   = MPShell.new(getOption)
    mprocess = false
    unless getOption(:nomonitor)
      if getOption(:readline)
        MPlayer.start_monitor
        mprocess = true
      else
        Thread.abort_on_exception = true
        Thread.new {
          ashell._pmonitor
        }
        if cpipe = getOption(:cpipe)
          Thread.new {
            ashell.remote_command(cpipe)
          }
        end
      end
    end
    ashell._run
    if mprocess
      MPlayer.stop_monitor
    end
  end

  def self.add_duration(limit = 10)
    DbAccess.instance
    limit = limit.to_i
    Song.find(:all, :conditions=>"duration<=60",
        :order=>"path", :limit=>limit).each do |rec|
      next unless test(?f, rec.path)
      cmd = "mplayer -identify -frames 1 -nosound -nograbpointer '#{rec.path}' 2>&1"
      result = `#{cmd}`
      output = result.grep(/ID_LENGTH/)[0]
      if output
        rec.duration = output.chomp.sub(/^.*=/,'').to_i
        rec.save
        Plog.info "Set #{rec.song}/#{rec.artist} to #{rec.duration}"
      end
    end
    true
  end
end

if ((__FILE__ == $0) && !defined?($mpshell_run))
  $mpshell_run = true
  MPShell.handleCli(
    ['--cache',     '-C', 1],   # Set kbytes to cache for video data
    ['--screen',    '-e', 1],   # Set screen number
    ['--fs',        '-f', 0],   # Set full screen
    ['--keep',      '-k', 0],   # Use playlist from last play
    ['--karaoke',   '-K', 0],   # Set karaoke mode
    ['--nomonitor', '-m', 0],   # Disable monitor in shell
    ['--config',    '-n', 1],   # Override default config
    ['--osd',       '-o', 1],
    ['--cpipe',     '-p', 1],   # Disable monitor in shell
    ['--readline',  '-r', 0],
    ['--sample',    '-s', 1],
    ['--sim',       '-S', 0],
    ['--volume',    '-V', 1],
    ['--verbose',   '-v', 0]
  )
end

