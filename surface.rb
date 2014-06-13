require 'json'
require 'active_support/all'
require 'ffi-geos'
require 'rgeo-geojson'
require 'rgeo'

require_relative './track'

RGeo::Geos.preferred_native_interface = :ffi

class Surface
  DEFAULT_DISTANCE_IN_METERS = 65

  DEFAULT_FRAMERATE = 1

  BUFFER_COEFFICIENT = 0.8

  attr_accessor :track

  def initialize(track)
    self.track = track
  end

  def meters_per_degree_at_latitude(latitude)
    radians = latitude * Math::PI / 180
    111132.92 - 559.82 * Math.cos(2 * radians) + 1.175 * Math.cos(4 * radians)
  end

  # given a lat/lon, a true north angle, and a distance, compute the point that's the given
  # number of meters away from the point
  def compute_angular_distance_point(theta, point, distance_in_meters=DEFAULT_DISTANCE_IN_METERS)
    xstart, ystart = point[1], point[0]

    distance = distance_in_meters / meters_per_degree_at_latitude(ystart)

    # for the 4 quadrants, convert to a right triangle along the x axis
    if theta >= 0 && theta <= 90
      theta = 90 - theta
      ysign = 1
      xsign = 1
    elsif theta > 90 && theta <= 180
      theta = theta - 90.0
      ysign = -1
      xsign = 1
    elsif theta > 180 && theta <= 270
      theta = 270 - theta
      ysign = -1
      xsign = -1
    else
      theta = theta - 270
      ysign = 1
      xsign = -1
    end

    opposite = ysign * distance * Math.sin(theta * Math::PI / 180)
    adjacent = xsign * distance * Math.cos(theta * Math::PI / 180)

    [ xstart + adjacent, ystart + opposite ]
  end

  # walk the track points at a given time interval (framerate) and compute angular
  # offset points at each node given the interpolated angle and location. After computing
  # the line, buffer it a constant distance to give an approximation of the coverage.
  def compute(distance_in_meters=DEFAULT_DISTANCE_IN_METERS, framerate=DEFAULT_FRAMERATE)
    frame_duration = 1000.0 / framerate

    current_timestamp = track.points.first[Track::IDX_TIMESTAMP]
    last_point_timestamp = track.points.last[Track::IDX_TIMESTAMP]

    offset_points = []
    track_points = []

    while current_timestamp <= last_point_timestamp
      last_point = track.find_previous_track_point(current_timestamp)
      next_point = track.find_next_track_point(current_timestamp)

      last_timestamp = last_point[Track::IDX_TIMESTAMP]
      next_timestamp = next_point[Track::IDX_TIMESTAMP]

      range = next_timestamp - last_timestamp

      percentage = (current_timestamp - last_timestamp) / range

      last_location = [last_point[Track::IDX_LATITUDE], last_point[Track::IDX_LONGITUDE]];
      next_location = [next_point[Track::IDX_LATITUDE], next_point[Track::IDX_LONGITUDE]];

      lon = ((next_location[1] - last_location[1]) * percentage) + last_location[1]
      lat = ((next_location[0] - last_location[0]) * percentage) + last_location[0]

      location = [ lat, lon ]

      last_heading = last_point[Track::IDX_HEADING]
      next_heading = next_point[Track::IDX_HEADING]

      heading_diff = next_heading - last_heading

      if heading_diff.abs > 180
        if next_heading > last_heading
          # counterclockwise across 0 degrees
          heading_diff = -last_heading - (360 - next_heading)
        else
          # clockwise across 0 degrees
          heading_diff = -(-(360 - last_heading) - next_heading)
        end
      end

      heading = (heading_diff * percentage) + last_heading

      if heading < 0
        heading += 360.0
      end

      heading_x, heading_y = compute_angular_distance_point(heading, location, distance_in_meters)

      current_timestamp += frame_duration

      offset_points << [ heading_x, heading_y ]

      track_points << [ lon, lat ]
    end

    return [nil, nil, nil] unless offset_points.count > 1

    line_geojson    = line_string_geojson(offset_points)
    polygon_geojson = buffered_line(lat, line_geojson, distance_in_meters)
    track_geojson   = line_string_geojson(track_points)

    [ track_geojson, line_geojson, polygon_geojson ]
  end

  def buffered_line(nominal_latitude, line_geojson, distance_in_meters)
    line = RGeo::GeoJSON.decode(line_geojson['geometry'], json_parser: :json, geo_factory: geometry_factory)

    buffer_distance_in_degrees = distance_in_meters / meters_per_degree_at_latitude(nominal_latitude)

    polygon = line.fg_geom.buffer(buffer_distance_in_degrees * BUFFER_COEFFICIENT, quad_segs: 4)
    polygon = geometry_factory._wrap_fg_geom(polygon, nil)

    polygon_geojson_geometry = RGeo::GeoJSON.encode(polygon)

    polygon_geojson = polygon_geojson(polygon_geojson_geometry)
  end

  def geometry_factory
    @geometry_factory ||= RGeo::Geos::FFIFactory.new(srid: 4326)
  end

  def polygon_geojson(polygon_geojson_geometry)
    { type: 'Feature',
      properties: {
       "fill" => '#0000ff'
      },
      geometry: polygon_geojson_geometry
    }.as_json
  end

  def line_string_geojson(coordinates)
    { type: 'Feature',
      properties: {},
      geometry: {
        type: 'LineString',
        coordinates: coordinates
      }
    }.as_json
  end
end
