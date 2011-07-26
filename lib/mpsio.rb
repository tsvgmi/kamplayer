#!/usr/bin/ruby

class SelectIO
  def initialize
    @rset    = []
    @wset    = []
    @eset    = []
    @timeout = nil
    @worklist = {}
  end

  def register(fid, mode, &handler)
    if @worklist[fid]
      return true
    end
    @worklist[fid] = handler
    case mode
    when :read
      @rset << fid
    when :write
      @wset << fid
    when :err
      @eset << fid
    else
      @rset << fid
    end
    true
  end

  def unregister(fid)
    if entry = @worklist[fid]
      @worklist.delete(fid)
      @rset.delete(fid)
      @wset.delete(fid)
      @eset.delete(fid)
      true
    else
      false
    end
  end

  def run
    while true
      rset, wset, eset = select(@rset, @wset, @eset, @timeout)
      rset.each do |fid|
        @worklist[fid].call(fid)
      end
      break if (@worklist.size <= 0)
    end
  end
end

selector = SelectIO.new
selector.register(STDIN, :read) do |fid|
  puts "Got it"
  data = fid.gets
  unless data
    selector.unregister(fid)
  end
  puts "Done"
end

fid = File.open("/Users/thienvuong/KA/monrem.fifo", File::NONBLOCK)
selector.register(fid, :read) do |fid|
  puts "Got it from fifo"
  data = fid.gets
  if data
    puts data
  else
    selector.unregister(fid)
  end
end

selector.run
