#!/usr/bin/env ruby
#---------------------------------------------------------------------------
# File:        vlcdriver.rb
# Date:        Sun Dec 02 20:47:39 -0800 2012
# Copyright:   E*Trade, 2012
# $Id$
#---------------------------------------------------------------------------
#++
require 'socket'
require 'kautils'

# Remote controller for Mplayer via its RC interface.  Use the input pipe
# to write command, and monitor output file for any status change.  Start
# method should be used here to setup the matching interface.
class VLCPlayerRC
  VPORT     = 9090

  include KAUtil

  def initialize(options = {})
    @options = options
    @trace   = options[:trace]
    @wchan   = nil
  end

  def start
    return if @options[:sim]
    unless is_process_running?("VLC.*extraintr.rc")
      cmd = "~/bin/vlc --extraintf rc --rc-host localhost:#{VPORT}"
      unless Pf.system("#{cmd} >vlc.log 2>&1 &", 1)
        raise "Cannot start player"
      end
    end
  end

  def stop
    kill_process("VLC.*-extraintf.rc", 9)
  end

  def channel
    unless @wchan
      @wchan = TCPSocket.open('localhost', VPORT)
    end
    @wchan
  end

  # Send a command to the slave and wait/process output.
  # Slave is async so we don't know when the response come and
  # whether the response is completed.  So have to wait.
  def drv_send(acmd, wait = 0)
    if @trace
      Plog.info "Sending #{acmd}"
    end
    return if @options[:sim]
    channel.puts("#{acmd}")
    channel.flush
    if wait > 0
      return get_response(wait)
    else
      return ""
    end
  end

  # Get a response from slave until timeout second
  private
  def get_response(timeout)
    while timeout > 0
      while line = channel.recv(80)
        break if line.empty?
        if true || @trace
          print line
        end
      end
      sleep 1
      timeout -= 1
    end
    return line
  end
end

class VLCPlayer
  attr_accessor :trace, :pmode, :cursong, :scan_mode, :playlist, :rc

  def initialize(playlist, options)
    @wchan   = nil
    @rc      = VLCPlayerRC.new(options)
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

  def method_missing(symbol, *data)
    @rc.drv_send("#{symbol.to_s} #{data.join(' ')}")
  end


  # Start the stand-alone monitor
  def self.bad_start_monitor
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

  def self.bad_stop_monitor
    kill_process("ruby.*pmonitor")
  end

  def stop(killit = false)
    if true
      drv_send "stop"
    else
      drv_send "shutdown"
      @rc.stop
    end
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
    drv_send("osd_show_text '#{msg}' 3000")
  end

  def drv_send(msg, wait = 0)
    @rc.drv_send(msg, wait)
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
        drv_send("clear")
        drv_send("enqueue #{file}")
        renew = false
      else
        drv_send("enqueue #{file}")
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
    drv_send "pausing_keep_force switch_audio #{mode}"
    drv_send 'seek -5 0'
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
        drv_send "atrack 1"
        drv_send "achan 1"
      else
        drv_send "atrack 2"
        drv_send "achan 1"
      end
    when 'S'
      if @pmode == :karaoke
        drv_send "atrack 2"
        drv_send "achan 1"
      else
        drv_send "atrack 1"
        drv_send "achan 1"
      end
    when 'L'
      if @pmode == :sound
        drv_send "achan 3"
      else
        drv_send "achan 4"
      end
    when 'R'
      if @pmode == :karaoke
        drv_send "achan 4"
      else
        drv_send "achan 3"
      end
    end

    case ksel[1,1]
    when 'W'
      drv_send 'switch_ratio 1.6667'
    when 'N'
      drv_send 'switch_ratio 1.3333'
    end

    drv_send "volume #{@volume}"
    drv_send "get_time", 1
  end

  def song_step(step)
    step  = step.to_i
    nstep = (step > 0) ? 1 : -1
    if step == 0
      drv_send 'seek 1 2'
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

    drv_send("pausing_keep_force pt_step #{acstep}", 3)
    if @scan_mode
      sleep 3
      drv_send "seek 60"
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
      drv_send "balance 2"
      @channel = :right
    else
      drv_send "balance -2"
      @channel = :left
    end
    drv_send "volume #{@volume} 1"
  end

  def switch_aspect
    if @aspect == :normal
      drv_send "switch_ratio 1.667"
      @aspect = :wide
    else
      drv_send "switch_ratio 1.333"
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
    drv_send "play"
    while true
      sleep 30
    end
  end
end


