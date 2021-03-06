function J = fn_Jacobian_dUv_dX(J, K, X, Zobs, nPoses, nPts, nIMUdata, ImuTimestamps, RptFeatureObs )
    %[J] = fnJacobian_dUv_dX( nJacs, idRow, idCol, K, x, nPoses, nPts, nIMUdata, ...
             %                   ImuTimestamps, RptFeatureObs, nUV )

    global PreIntegration_options
    
    %% Objective function elements: ei = (ui' - ui)^2, ei'= (vi' - vi)^2 (i=1...N)
    % Find R, T corresponding to 3D points pi and pi'.
    % 
    % K: camera model
    % p3d0: 3D points at the first camera pose
    % x: current estimate of the states (alpha, beta, gamma, T)

    %tmpv = zeros(1, nJacs);
    tidend = 0;
    zid = 0;
    
    
    %nObsId_FeatureObs = 2;
    fx = K(1,1); cx0 = K(1,3); fy = K(2,2); cy0 = K(2,3);

    % Section for pose 1    
    a_u2c = X.Au2c.val(1); b_u2c = X.Au2c.val(2); g_u2c = X.Au2c.val(3);    
    Ru2c = fn_RFromABG(a_u2c, b_u2c, g_u2c); %fRx(alpha) * fRy (beta) * fRz(gamma);         
    Tu2c = X.Tu2c.val;

    %%%%%%%%%
    a_cat = zeros(nPoses, 1);
    b_cat = a_cat;
    g_cat = a_cat;
    Ru_cat = zeros(3,3,nPoses);
    Tu_cat = zeros(3,nPoses);
    Rc_cat = zeros(3,3,nPoses);
    Tc_cat = zeros(3,nPoses);
    
    for(frm_id = 1:nPoses)        
        if(frm_id > 1)
            if((PreIntegration_options.bUVonly == 1) || (PreIntegration_options.bPreInt == 1))
                pid = frm_id - 1;
            else
                pid = ImuTimestamps(frm_id) - ImuTimestamps(1);
            end
            Au_cat = X.pose(pid).ang.val;
            a_cat(frm_id) = Au_cat(1); b_cat(frm_id) = Au_cat(2);  g_cat(frm_id) = Au_cat(3);
            Ru_cat(:,:,frm_id) = fn_RFromABG(a_cat(frm_id), b_cat(frm_id), g_cat(frm_id));%fRx(alpha) * fRy (beta) * fRz(gamma);            
            Tu_cat(:,frm_id) = X.pose(pid).trans.xyz;
            
        else % frm_id ==1, Ru2c,Tu2c
            
            a = 0; b = 0; g = 0;
            Ru_cat(:,:,frm_id) = eye(3); 
            
        end
        
        Rc_cat(:,:,frm_id) = Ru2c * Ru_cat(:,:,frm_id);
        Tc_cat(:,frm_id) = (Ru_cat(:,:,frm_id))' * Tu2c + Tu_cat(:,frm_id);        
    end
    
    %%%%%%%%%
    % Section for all of the poses
    for(fid=1:nPts)
        
        nObs = RptFeatureObs(fid).nObs;
        
        for(oid=1:nObs)
            
            frm_id = RptFeatureObs(fid).obsv(oid).pid; 
            if(frm_id > nPoses)
                break;
            end
            
            a = a_cat(frm_id); b = b_cat(frm_id); g = g_cat(frm_id);
            Ru = Ru_cat(:,:,frm_id); Tu = Tu_cat(:,frm_id);
            Rc = Rc_cat(:,:,frm_id); Tc = Tc_cat(:,frm_id);

            p3d1 = Rc * (X.feature(fid).xyz - Tc);    
            
            [duvd] = fn_dUv_dCamFxyz_dr(p3d1, fx, fy, 1);
            [dxyz,dxyz_u2c, ~] = fn_dCamFxyz_dWldFxyz_dCamU2c(a, b, g, a_u2c, b_u2c, g_u2c, Ru, Ru2c, ...
                                                    Tu, Tu2c, X.feature(fid).xyz, 1);
                                                
            % d(xyz)/d(xyz)f
            dfxyz = Rc;
            
            %% d(uv)/d(xyz)f
            duvdfxyz = duvd(1:2,:) * dfxyz;        
            
            %% d(uv)/d(abgxyz)u2c part
            duvdxyz_u2c = duvd(1:2,:) * dxyz_u2c;                    

            %% d(uv)/d(abgxyz)c, 2x6
            if(frm_id == 1)  %dxf,dyf,dzf, (da,db,dg,dx,dy,dz)u2c
                
                zid = zid + 1;
                row = Zobs.fObs(zid).row;
                
                col = (X.feature(fid).col(:))';
                J.dUv_dX(zid).dFxyz.val = (duvdfxyz(:))';
                J.dUv_dX(zid).dFxyz.row = [ row(1) * ones(1, 3) ; row(2) * ones(1, 3) ]; 
                J.dUv_dX(zid).dFxyz.col = [ col; col ]; 
                                
                col = [X.Au2c.col(:); X.Tu2c.col(:)]';
                clen = length(col);
                rlen = length(row);
                assert( rlen*clen == length(duvdxyz_u2c(:)) );
                J.dUv_dX(zid).dATu2c.val = (duvdxyz_u2c(:))';                
                J.dUv_dX(zid).dATu2c.row = [ row(1) * ones(1, clen) ; row(2) * ones(1, clen) ]; 
                J.dUv_dX(zid).dATu2c.col = [ col ; col ]; 
                
                J.dUv_dX(zid).dAbgxyz_1 = []; %delete
                
            else % frm_id > 1    
                
                zid = zid + 1;
                row = Zobs.fObs(zid).row;
                
                duvddabgxyz = duvd(1:2,:) * dxyz;                
                
                if((PreIntegration_options.bUVonly == 1) || (PreIntegration_options.bPreInt == 1))
                    pid = frm_id - 1;
                else
                    pid = ImuTimestamps(frm_id) - ImuTimestamps(1);
                end
                col = [(X.pose(pid).ang.col(:))', (X.pose(pid).trans.col(:))'];
                J.dUv_dX(zid).dAbgxyz_1.val = (duvddabgxyz(:))';
                J.dUv_dX(zid).dAbgxyz_1.row = [ row(1) * ones(1,6); row(2) * ones(1,6) ];
                J.dUv_dX(zid).dAbgxyz_1.col = [ col; col ];
                
                col = (X.feature(fid).col(:))';
                J.dUv_dX(zid).dFxyz.val = (duvdfxyz(:))';
                J.dUv_dX(zid).dFxyz.row = [ row(1) * ones(1,3); row(2) * ones(1,3) ];
                J.dUv_dX(zid).dFxyz.col = [ col; col ];
                                
                col = [X.Au2c.col(:); X.Tu2c.col(:)]';
                clen = length(col);
                rlen = length(row);
                assert( rlen*clen == length(duvdxyz_u2c(:)) );
                J.dUv_dX(zid).dATu2c.val = (duvdxyz_u2c(:))';
                J.dUv_dX(zid).dATu2c.row = [ row(1) * ones(1, clen) ; row(2) * ones(1, clen) ]; 
                J.dUv_dX(zid).dATu2c.col = [ col ; col ]; 
                
            end             
        end
    end
    
    return;
        