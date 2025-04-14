function [imgStack] = loadTifDir_numFiles(fileName,numFiles)
dirName = cd;
tifFiles = dir(fileName);
desiredImgDimensions = 1;%2;
            imgStack = [];
            tic;
            for(currentFile = 1:numFiles)
                disp(['Reading image stack ' num2str(currentFile) ' out of ' num2str(length(tifFiles))]);
                filePath = [dirName '\' tifFiles(currentFile).name];
                % Read images into tifStack
                temp = read_Tiffs(filePath,1,100);
                %temp=ScanImageTiffReader(filePath).data();
                imgStack = cat(3,imgStack,temp(:,:,:));
                %imgStack = cat(3,imgStack,ScanImageTiffReader(filePath).data());
            end;
            toc;
end

