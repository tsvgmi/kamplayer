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
    p "Player: #{acmd}"
    @wchan.flush
  end

  def self.send(command)
    get_player.send(command)
  end

end
