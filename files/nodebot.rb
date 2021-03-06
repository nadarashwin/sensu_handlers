#!/usr/bin/env ruby

require "strscan"
require "#{File.dirname(__FILE__)}/base"

class Nodebot < BaseHandler
  def pager_channel_keys
    %w[ pages_irc_channel ]
  end

  def channel_keys
    %w[ irc_channels notifications_irc_channel ]
  end

  def channels
    # # Return channels, but strip out any "#", nodebot doesn't need them
    super.flatten.uniq.collect { |x| x.gsub(/#/, '') }
  end

  def message
    case @event['check']['status']
    when 0
      status = 'OK'
      color  = '9'
    when 1
      status = 'WARNING'
      color = '8'
    when 2
      status = 'CRITICAL'
      color = '4'
    else
      status = 'UNKNOWN'
      color = '7'
    end

    # Max irc line length is theoretically 512 from the RFC, but after the
    # color, line breaks etc it comes out to ~ 419 for us? Just truncate
    # to 415 to be safe
    timestamp = Time.now().strftime("%F %T")
    pre = "[sensu] #{color} #{status} - "
    post = " (#{timestamp})"
    body = description(415 - pre.length - post.length, uncolorize=false)
    body = ansi_to_irc_colors(body)
    "#{pre}#{body}#{post}"
  end

  def handle
    channels.each do |channel|
      send(channel, message)
    end
  end

  def send(channel, message)
    system('nodebot', channel, message)
  end

end

ANSI_TO_IRC_COLORS = {
  30 => "01",  # black
  31 => "04",  # red
  32 => "09",  # green
  33 => "08",  # yellow
  34 => "02",  # blue
  35 => "13", # pink
  36 => "11", # cyan
  37 => "00",  # white
  39 => "00",   # white
}
# Background colors
ANSI_TO_IRC_BACK = {}
ANSI_TO_IRC_COLORS.each do |k, v|
  ANSI_TO_IRC_BACK[k + 10] = v
end
# Formatting characters
ANSI_TO_IRC_FMT = {
  0  => 0xf,  # reset
  1  => 0x2,  # bold
  4  => 0x1f, # underline
  7  => 0x16, # reverse mode
}
ANSI_START = Regexp.new(Regexp.quote("\x1b"))

def ansi_to_irc_colors(message)
  output = ""
  scanner = StringScanner.new(message)

  token = scanner.scan_until(ANSI_START)
  # No ANSI sequences :(
  if !token
     return message
  end

  while token
    # Remove the ANSI escape sequence
    # and append whatever is left to
    # the output
    output << token[0...-1]

    next_byte = scanner.get_byte()
    if next_byte >= "0x40" && next_byte <= "0x7E"
      # Already reached the end of the sequence?
      # Do nothing.
    elsif next_byte == "["
      sequence = scanner.scan_until(/[\x40-\x7E]/)
      if sequence
        # Discard the final byte
        sequence = sequence[0...-1]
        # Split by semicolon
        sequence = sequence.split(";")

        foreground = nil
        background = nil
        formatting = nil
        sequence.each do |ansi_code|
          ansi_code = Integer(ansi_code) rescue nil
          next unless ansi_code

          foreground ||= ANSI_TO_IRC_COLORS[ansi_code]
          background ||= ANSI_TO_IRC_BACK[ansi_code]
          formatting ||= ANSI_TO_IRC_FMT[ansi_code]
       end

        if foreground
          output << "\x03"
          output << foreground
        end
        if background
          # Background specified, but no foreground
          # IRC requires foreground first, then background
          # so we send 99 to force the default foreground
          if !foreground
            output << "\x0399"
          end
          output << ","
          output << background
        end
        if formatting
          output << formatting.chr
        end
      end
    else
      # not a color, not much we can do about this
      scanner.scan_until(/[\x40-\x7E]/)
    end

    token = scanner.scan_until(ANSI_START)
  end
  # Consume anything left
  output << scanner.rest()
end

