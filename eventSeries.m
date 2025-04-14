classdef eventSeries < handle
    %eventSeries Summary of this class goes here
    %   Detailed explanation goes here
    
    properties
        next
        current
    end
    
    properties (Dependent = true)
        past
    end
    
    properties (SetAccess = private, Hidden = true)
        defaultDataStruct
        numberOfPastEvents = 0;
        pastPrealloc
    end
    
    % Properties needed for backwards compatibility:
    properties (Access = private, Hidden = true)
        dateCreated % To allow updating of old saved objects of this class.
        currentCached
        pastPrealloc2
    end
    
    properties (Dependent = true, Hidden = true)
        nAlloc
    end
    
    methods
        function evt = eventSeries(dataStruct)
            % Validate dataStruct. Types must be array-able, i.e. no strings:
            for field = fieldnames(dataStruct)'
                if ischar(dataStruct(1).(field{:}))
                    error('eventSeries input struct must not contain fields with strings. Use cells of strings instead.')
                end
            end
            
            % Create frame structures. Next is filled with defaults, others
            % are empty:
            evt.defaultDataStruct = dataStruct;
            
            evt.next = evt.defaultDataStruct;
            evt.current = evt.defaultDataStruct;
            evt.pastPrealloc = evt.defaultDataStruct;
            
            % Store date to allow updating of old saved objects of this
            % class:
            evt.dateCreated = now;
        end
        
        function advance(evt)
            % Advance events: NEXT becomes current and is added to PAST.
            evt.numberOfPastEvents = evt.numberOfPastEvents+1;
            nCurrent = max(evt.numberOfPastEvents-1, 1);
            nNext = evt.numberOfPastEvents;
            
            % Since evt.past is a structure of arrays, we have to go through
            % each field and add the new event:
            for field = fieldnames(evt.next)'
                evt.pastPrealloc(1).(field{:})(nCurrent) = evt.current.(field{:});
                evt.pastPrealloc(1).(field{:})(nNext) = evt.next.(field{:});
            end
            
            % We remember separately what the current event was, for
            % convenience.
            evt.current = evt.next;
        end
        
        function preallocate(evt, n)
            % Pre-allocates n elements for the evt.past vectors.
            for field = fieldnames(evt.pastPrealloc)'
                evt.pastPrealloc(1).(field{:})(evt.numberOfPastEvents+(1:n)) = ...
                    evt.pastPrealloc(1).(field{:})(end);
            end
        end
        
        function deallocate(evt)
            % Removes pre-allocated but unused space:
            if ~isempty(evt.pastPrealloc)
                for field = fieldnames(evt.pastPrealloc)'
                    evt.pastPrealloc(1).(field{:})(evt.numberOfPastEvents+1:end) = [];
                end
            end
        end
        
        function nAlloc = get.nAlloc(evt)
            fields = fieldnames(evt.pastPrealloc)';
            nAlloc = numel(evt.pastPrealloc(1).(fields{1}));
        end
        
        function set.past(evt, val)
            evt.pastPrealloc = val;
            evt.pastPrealloc2 = val;
            
            fields = fieldnames(val)';
            evt.numberOfPastEvents = numel(val.(fields{1}));
            
            % Update "current" when "past" is changed:
            for field = fields
                if ~isempty(val.(field{:}))
                    evt.current.(field{:}) = val.(field{:})(end);
                end
            end
        end
        
        function past = get.past(evt)
            fields = fieldnames(evt.pastPrealloc)';
            if evt.nAlloc == evt.numberOfPastEvents
                past = evt.pastPrealloc;
            else
                for field = fields
                    past.(field{:}) = evt.pastPrealloc(1).(field{:})(1:evt.numberOfPastEvents);
                end
            end
            
            % Always get last element in "past" from "current":
            if numel(past.(fields{1})) > 0
                for field = fields
                    if ~isempty(past.(field{:}))
                        past.(field{:})(end) = evt.current.(field{:});
                    end
                end
            end
        end
        
        function evts = getEvents(evt, ind)
            % Return events as specified in indices:
            fields = fieldnames(evt.pastPrealloc)';
            for field = fields
                evts.(field{:}) = evt.pastPrealloc(1).(field{:})(ind);
            end
        end
        
        function evt = saveobj(evt)
            % Automatically de-allocate upon saving:
            evt.deallocate;
        end
        
        function mat = evt2mat(evt, ind)
            % Get matrix of past events, indexed by ind.
            if nargin<2
                ind = 1:evt.numberOfPastEvents;
            end
            
            fields = fieldnames(evt.pastPrealloc)';
            
            mat = nan(numel(fields), numel(ind), 'double');
            
            for f = 1:numel(fields)
                if ~iscell(evt.pastPrealloc(1).(fields{f})(ind))
                    mat(f, :) = evt.pastPrealloc(1).(fields{f})(ind);
                end
            end
        end
        
        function mat2evt(evt, mat)
            % Restore eventseries from data matrix.
            fields = fieldnames(evt.pastPrealloc)';
            for f = 1:numel(fields)
                if isequal(unique(mat(f, :)), [0 1])
                    % Logical array:
                    evt.past(1).(fields{f}) = logical(mat(f, :));
                elseif all(isnan(mat(f, :)))
                    % Unsupported data type (i.e. cannot be converted to
                    % number), e.g. cell: Do nothing.
                    continue
                else
                    evt.past(1).(fields{f}) = mat(f, :);
                end
            end
        end
        
        function addField(evt, name, value)
            f = fieldnames(evt.pastPrealloc)';
            if size(value) ~= size(evt.pastPrealloc.(f{1}))
                error('Value of new field must have same size as existing fields.')
            end
            evt.pastPrealloc.(name) = value;
        end
        
        function renameField(evt, old, new)
            for f = fieldnames(evt.pastPrealloc)'
                if strcmp(f{:}, old)
                    pastNew.(new) = evt.pastPrealloc.(old);
                else
                    pastNew.(f{:}) = evt.pastPrealloc.(f{:});
                end
            end
            evt.pastPrealloc = pastNew;
        end
    end
    
    methods (Static = true)
        function evt = loadobj(evtLoaded)
            if isstruct(evtLoaded)
                % If no other instance of the class is in memory, input will be a struct
                evt = eventSeries.update(eventSeries(evtLoaded.defaultDataStruct));
                fields = fieldnames(evtLoaded);
                for field = fields'
                    if strcmp(field{:}, 'past')
                        % This is necessary for very old versions of the class:
                        if evtLoaded.numberOfPastEvents==0
                            evt.pastPrealloc = evtLoaded.defaultDataStruct;
                        else
                            evt.pastPrealloc = evtLoaded.(field{:});
                        end
                    else
                        evt.(field{:}) = evtLoaded.(field{:});
                    end
                end
            else
                evt = eventSeries.update(evtLoaded);
                if evtLoaded.numberOfPastEvents==0 || isempty(evt.pastPrealloc)
                    evt.pastPrealloc = evtLoaded.defaultDataStruct; % In case saved obj didn't have pastPrealloc.
                else
                    evt.pastPrealloc = evtLoaded.past; % In case saved obj didn't have pastPrealloc.
                end
            end
                        
        end
        
        function evt = update(evt)
            % This function updates old versions of the object.
            
            if isempty(evt.dateCreated) || evt.dateCreated < 736448
                % evt.current was changed from a dependent to a full
                % property to increase speed, so for objects where it was
                % saved as a dependent property, we have to fill it:
                evt.current = evt.currentCached;
            end
        end
    end
end

