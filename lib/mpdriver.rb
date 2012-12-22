#!/usr/bin/env ruby
#---------------------------------------------------------------------------
# File:        mpdriver.rb
# Date:        Sun Dec 02 21:24:18 -0800 2012
# Copyright:   E*Trade, 2012
# $Id$
#---------------------------------------------------------------------------
#++
require 'kautils'

# Remote controller for Mplayer via its RC interface.  Use the input pipe
# to write command, and monitor output file for any status change.  Start
# method should be used here to setup the matching interface.
class MPlayerRC
  MINPUT     = "mp.input"
  MOUTPUT    = "mp.output"

  attr_reader :rchan    # Reader channel from slave (get output)
  attr_reader :wchan    # Writer channel to slave (send command)

  include KAUtil

  def initialize(options = {})
    @options = options
    @trace   = options[:trace]
    @wchan   = nil
    unless test(?f, MOUTPUT)
      File.open(MOUTPUT, "w") {}
    end
    @rchan = File.open(MOUTPUT)
    @rchan.seek(0, 2)
    @ismonitor = nil
  end

  def start
    return if @options[:sim]
    cache = @options[:cache] || 8000
    self.stop
    unless test(?p, MINPUT)
      Pf.system("mkfifo #{MINPUT}", 1)
    end
    popt = "-autosync 30 -slave -quiet -framedrop -rootwin -nograbpointer -idle"
    if osd = @options[:osd]
      popt += " -osdlevel #{osd}"
    end
    if @options[:fs]
      popt += " -fs"
    else
      popt += " -geometry 0:0"
    end
    if screen = @options[:screen]
      popt += " -xineramascreen #{screen}"
    end
    Pf.system("mplayer -idx -cache #{cache} #{popt} -input file=#{MINPUT} >>#{MOUTPUT} 2>&1 &", 1)
  end

  def stop
    kill_process("mplayer.*-slave")
  end

  # Send a command to the slave and wait/process output.
  # Slave is async so we don't know when the response come and
  # whether the response is completed.  So have to wait.
  def send(acmd, wait = 0)
    if @trace
      Plog.info "Sending #{acmd}"
    end
    return if @options[:sim]
    unless @wchan
      @wchan = File.open(MINPUT, "w")
    end

    # 1st interaction.  Discard previous output
    unless @ismonitor
      @rchan.seek(0, 2)
      @ismonitor = true
    end

    @wchan.puts("#{acmd}")
    @wchan.flush
    if wait > 0
      get_response(wait)
    end
  end

  # Get a response from slave until timeout second
  private
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

  public

  # Monitor the slave output and callback for each line
  # - Sleep when output is drained and retry after 1 sec
  # - Issue get each 5 secs to get song current position
  def monitor_for(options = {})
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
      if fptimer = options[:filepos]
        scount += 1
        if scount >= fptimer
          send "status"
          scount = 0
        end
      end
    end
    false
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

  def start
    @rc.start
  end

  def rewind
    send "seek 1 2"
  end

  def switch_track
    switch_audio
    send "volume #{@volume} 1"
  end
  
  def fullscreen
    send "vo_fullscreen"
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
    kill_process("ruby.*pmonitor")
  end

  def stop(killit = false)
    send "stop"
    @rc.stop
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
      STDERR.print("."); STDERR.flush
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
        switch_audio 2
      else
        if omode && (omode == :sound)
          switch_audio
        end
      end
    when 'S'
      if @pmode == :karaoke
        switch_audio
      else
        if omode && (omode == :karaoke)
          switch_audio
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

  # Monitor the file being played.
  # When mplayer switch to new song, it will be detected here.
  # - Detect song playtime and update db
  # - Detect end of song and play end sounds
  # - Detect end of mplayer
  def monitor_curfile
    file    = nil
    @rc.monitor_for(:filepos=>5) do |line, lcnt|
      case line
      when /^Playing\s+/
        file = $'.chomp.sub(/\.$/, '')
        unless file.empty?
          @lastfile = file
          if true
            yield :file_changed, file
          else
            if @options[:verbose]
              Plog.info "Detect #{File.basename(file)}"
            end
            return file
          end
        end
      when /^Exiting\.\.\./
        Plog.warn "#{lcnt}. Mplayer exit ******"
        yield :player_exit
      when /ANS_LENGTH=/
        duration = $'.sub(/\..*$/, '')
        yield :length, duration
      when /ANS_PERCENT_POSITION=/
        yield :percent_position, $'.strip.to_i
      when /MPlayer interrupted by signal/
        Plog.warn line
        yield :player_exit
      end
      false
    end
  end
end


