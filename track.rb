class Track
  IDX_TIMESTAMP = 0
  IDX_LATITUDE  = 1
  IDX_LONGITUDE = 2
  IDX_HEADING   = 8

  attr_accessor :points

  def initialize(json)
    self.points = json
  end

  def find_previous_track_point_index(time)
    points.each_with_index do |point, i|
      timestamp = points[i][IDX_TIMESTAMP];
      if timestamp > time
        return i - 1 < 0 ? 0 : i - 1
      end
    end
    0
  end

  def find_previous_track_point(time)
    index = find_previous_track_point_index(time)
    points[index]
  end

  def find_next_track_point(time)
    index = find_previous_track_point_index(time) + 1
    index < points.count ? points[index] : points.last;
  end
end
