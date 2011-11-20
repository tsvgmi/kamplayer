class Player
  MINPUT     = "#{ENV['HOME']}/KA/mp.input"
  MOUTPUT    = "#{ENV['HOME']}/KA/mp.output"

  @@player = nil
  def self.get_player
    unless @@player
      @@player = self.new
    end
    @@player
  end

  @@pldisable = false
  def self.disable
    @@pldisable = true
  end

  def self.start
    unless test(?p, MINPUT)
      system("mkfifo #{MINPUT}")
    end
    cmd = "mplayer -idx -cache 8000 -autosync 30 -slave -quiet -framedrop -rootwin -vf yadif -nograbpointer -vf scale -idle -double -fs -xineramascreen 1 -input file=#{MINPUT}"
    system "#{cmd} >>#{MOUTPUT} 2>&1 &"
    system "katool mpmonitor -k >>monitor.log 2>&1 &"
    #system "mpshell.rb -c -k pmonitor >>monitor.log 2>&1 &"
  end

  def self.stop
    ['mplayer.*-slave', 'mpshell.rb.*pmonitor'].each do |ptn|
      pids = `ps -ax`.grep(/#{ptn}/).map do |aline|
        aline.split.first.to_i
      end
      if pids.size > 0
        Process.kill("HUP", *pids)
        sleep(1)
      end
    end
    true
  end

  def initialize
    @wchan = nil
    unless test(?f, MOUTPUT)
      File.open(MOUTPUT, "w") {}
    end
    @rchan = File.open(MOUTPUT)
    @rchan.seek(0, 2)
  end

  def send(acmd)
    if @@pldisable
      return
    end
    unless @wchan
      @wchan = File.open(MINPUT, "w")
    end
    @wchan.puts("#{acmd}")
    Rails.logger.debug "Player: #{acmd}"
    @wchan.flush
  end

  def self.send(command)
    get_player.send(command)
  end

end
