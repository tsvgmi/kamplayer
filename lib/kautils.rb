module KAUtil
  def kill_process(ptn, sig = "HUP")
    Plog.warn "Stopping process #{ptn}"
    pids = pids_of(ptn)
    if pids.size > 0
      Process.kill(sig, *pids)
      sleep(1)
    end
    pids
  end

  def pids_of(ptn)
    `pgrep -lf #{ptn}`.map { |aline| aline.split.first.to_i }
  end

  def is_process_running?(ptn)
    pids_of(ptn).size > 0
  end
end

