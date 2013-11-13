#
# Fluentd
#
#    Licensed under the Apache License, Version 2.0 (the "License");
#    you may not use this file except in compliance with the License.
#    You may obtain a copy of the License at
#
#        http://www.apache.org/licenses/LICENSE-2.0
#
#    Unless required by applicable law or agreed to in writing, software
#    distributed under the License is distributed on an "AS IS" BASIS,
#    WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#    See the License for the specific language governing permissions and
#    limitations under the License.
#
module Fluentd
  module Plugin

    #
    # RoutingOutput is a special output plugin that forwards
    # events to other output plugins.
    #
    class RoutingOutput < Output
      def emit(tag, time, record)
        match(tag).emit(tag, time, record)
      end

      def emits(tag, es)
        match(tag).emits(tag, es)
      end

      # must be implemented in the extending class
      def match(tag)
        raise NoMethodError, "#{self.class}#match is not implemented"
      end
    end

  end
end
