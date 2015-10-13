Plugin.create(:undo_send) do
  # TODO: Changable
  Delay = 1

  class CancelableQueue
    def initialize
      @q = []
      @m = Mutex.new
    end

    # @param [Any] msg
    def push(data)
      @q.push(data: data, alive: true)
    end

    # if data is dead, returns nil
    # @return [Any|nil]
    def shift
      @m.synchronize do
        v = @q.shift
        return nil unless v[:alive]
        return v[:data]
      end
    end

    # 一番先頭をキャンセルする
    # @return [Any] Assigned data
    def cancel
      @m.lock
      res = nil

      @q.each do |t|
        next unless t[:alive]
        t[:alive] = false
        res = t[:data]
        break
      end

      return res
    ensure
      @m.unlock
    end
  end

  q = CancelableQueue.new

  # @param [String] text
  def sysmsg(text)
    Plugin.call(:update, nil, [Message.new(message: text, system: true)])
  end

  command(
    :undoable_tweet,
    name: 'undoable tweet',
    condition: lambda{ |opt| true },
    visible: true,
    role: :postbox
  ) do |opt|
    text = Plugin.create(:gtk).widgetof(opt.widget).widget_post.buffer.text
    next if text.empty?

    q.push(message: text, service: Service.primary)
    Plugin.create(:gtk).widgetof(opt.widget).widget_post.buffer.text = ''

    Reserver.new(Delay) do
      d = q.shift
      next unless d
      d[:service].update(message: d[:message])
    end

    sysmsg("ツイートを予約しました。#{Delay}秒以内なら信頼を失わずにキャンセル可能! message: #{text}")
  end

  command(
    :cancel_undoable_tweet,
    name: 'cancel undoable tweet',
    condition: lambda{ |opt| true },
    visible: true,
    role: :postbox,
  ) do |opt|
    d = q.cancel
    next unless d

    Plugin.create(:gtk).widgetof(opt.widget).widget_post.buffer.text = d[:message]
    sysmsg("ツイートをキャンセルしたよ。メッセージを修正して信頼を失わないようなツイートにしよう!")
  end
end
