module DbSucker
  class Application
    class Tie
      def self.descendants
        @descendants ||= []
      end

      # Descendant tracking for inherited classes.
      def self.inherited(descendant)
        descendants << descendant
      end

      def self.hook_all! app
        descendants.uniq.each do |klass|
          app.debug "[AppTie] Loading apptie `#{klass.name}'"
          klass.hook!(app)
        end
      end

      def self.hook! app
        raise NotImplementedError, "AppTies must implement class method `.hook!(app)'!"
      end
    end
  end
end
